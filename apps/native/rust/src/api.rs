use crate::frb_generated::StreamSink;
use anyhow::{anyhow, Result};
use futures_util::{SinkExt, StreamExt};
use std::{
    collections::HashMap,
    sync::{Mutex, OnceLock},
};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    sync::mpsc,
};
use tokio_tungstenite::{
    connect_async,
    tungstenite::{
        protocol::{frame::coding::CloseCode, CloseFrame},
        Message,
    },
};
use vnc::{PixelFormat, VncConnector, VncEncoding, VncEvent, X11Event};

pub struct ScreenFrame {
    pub width: u32,
    pub height: u32,
    pub pixels: Vec<u8>,
    pub detail: String,
    pub close_code: u16,
}
pub struct ScreenInput {
    pub kind: String,
    pub x: u16,
    pub y: u16,
    pub buttons: u8,
    pub key: u32,
    pub down: bool,
    pub text: String,
}
static INPUTS: OnceLock<Mutex<HashMap<String, mpsc::UnboundedSender<ScreenInput>>>> =
    OnceLock::new();
fn inputs() -> &'static Mutex<HashMap<String, mpsc::UnboundedSender<ScreenInput>>> {
    INPUTS.get_or_init(|| Mutex::new(HashMap::new()))
}
#[flutter_rust_bridge::frb(sync)]
pub fn screen_input(id: String, input: ScreenInput) -> Result<()> {
    inputs()
        .lock()
        .unwrap()
        .get(&id)
        .ok_or_else(|| anyhow!("Screen disconnected"))?
        .send(input)?;
    Ok(())
}

/// This bridge only transports the existing authenticated WSS and decodes RFB.
/// Hermes remains the authority for profiles, displays and who may send input.
pub async fn watch_screen(id: String, url: String, sink: StreamSink<ScreenFrame>) -> Result<()> {
    let (sender, mut receiver) = mpsc::unbounded_channel();
    inputs().lock().unwrap().insert(id.clone(), sender);
    let result = run_screen(url, &mut receiver, &sink).await;
    inputs().lock().unwrap().remove(&id);
    let (close_code, detail) = match result {
        Ok(exit) => exit,
        Err(error) => (1011, error.to_string()),
    };
    let _ = sink.add(ScreenFrame {
        width: 0,
        height: 0,
        pixels: vec![],
        detail,
        close_code,
    });
    Ok(())
}

async fn run_screen(
    url: String,
    receiver: &mut mpsc::UnboundedReceiver<ScreenInput>,
    sink: &StreamSink<ScreenFrame>,
) -> Result<(u16, String)> {
    let (ws, _) = connect_async(url).await?;
    let (mut send, mut recv) = ws.split();
    let (vnc_io, bridge_io) = tokio::io::duplex(1024 * 1024);
    let (mut read, mut write) = tokio::io::split(bridge_io);
    let (close, mut closing) = mpsc::unbounded_channel::<u16>();
    let mut network = tokio::spawn(async move {
        let mut bytes = vec![0; 65536];
        loop {
            tokio::select! {
              biased;
              Some(code) = closing.recv() => {
                send.send(Message::Close(Some(CloseFrame { code: CloseCode::from(code), reason: if code == 1000 { "Viewer closed" } else { "Viewer suspended" }.into() }))).await?;
                return Ok::<_, anyhow::Error>((code, "Screen connection closed".to_owned()));
              },
              frame = recv.next() => match frame {
                Some(Ok(Message::Binary(data))) => write.write_all(&data).await?,
                Some(Ok(Message::Close(frame))) => {
                  return Ok(frame.map(|f| (u16::from(f.code), f.reason.to_string())).unwrap_or((1005, "Screen closed".into())));
                },
                Some(Ok(Message::Ping(data))) => send.send(Message::Pong(data)).await?,
                Some(Err(error)) => return Err(error.into()),
                None => return Ok((1006, "Screen disconnected".into())),
                _ => {},
              },
              count = read.read(&mut bytes) => {
                let count = count?;
                if count == 0 { return Ok((1006, "RFB connection ended".into())); }
                send.send(Message::Binary(bytes[..count].to_vec().into())).await?;
              },
            }
        }
    });
    let starting = async {
        VncConnector::new(vnc_io)
            .set_auth_method(async { Ok(String::new()) })
            .add_encoding(VncEncoding::Zrle)
            .add_encoding(VncEncoding::CopyRect)
            .add_encoding(VncEncoding::Raw)
            .allow_shared(true)
            .set_pixel_format(PixelFormat::bgra())
            .build()?
            .try_start()
            .await?
            .finish()
    };
    let client = tokio::select! {
      ready = starting => match ready { Ok(client) => client, Err(error) => { network.abort(); return Err(error.into()); } },
      ended = &mut network => return ended?,
    };
    let mut width = 0usize;
    let mut height = 0usize;
    let mut pixels = Vec::<u8>::new();
    let mut tick = tokio::time::interval(std::time::Duration::from_millis(33));
    let mut dirty = false;
    client.input(X11Event::FullRefresh).await?;
    let outcome: Result<(u16, String)> = async {
    loop {
      tokio::select! {
        ended = &mut network => return ended?,
        input = receiver.recv() => {
          let Some(input) = input else { return Ok((1006, "Viewer detached".into())); };
          let event = match input.kind.as_str() {
            "close" | "pause" => {
              close.send(if input.kind == "close" { 1000 } else { 4002 })?;
              return (&mut network).await?;
            },
            "pointer" => X11Event::PointerEvent((input.x, input.y, input.buttons).into()),
            "key" => X11Event::KeyEvent((input.key, input.down).into()),
            "paste" => X11Event::CopyText(input.text),
            _ => continue,
          };
          client.input(event).await?;
        },
        event = client.recv_event() => {
            match event? {
              VncEvent::SetResolution(size) => {
                width = size.width as usize; height = size.height as usize;
                pixels = vec![255; width * height * 4];
              },
              VncEvent::RawImage(rect, data) => {
                for row in 0..rect.height as usize {
                  let dest = ((rect.y as usize + row) * width + rect.x as usize) * 4;
                  let src = row * rect.width as usize * 4;
                  pixels[dest..dest + rect.width as usize * 4].copy_from_slice(&data[src..src + rect.width as usize * 4]);
                }
                dirty = true;
              },
              VncEvent::Copy(dst, src) => {
                let snapshot = pixels.clone();
                for row in 0..dst.height as usize {
                  let from = ((src.y as usize + row) * width + src.x as usize) * 4;
                  let to = ((dst.y as usize + row) * width + dst.x as usize) * 4;
                  pixels[to..to + dst.width as usize * 4].copy_from_slice(&snapshot[from..from + dst.width as usize * 4]);
                }
                dirty = true;
              },
              VncEvent::Error(reason) => return Err(anyhow!(reason)),
              _ => {}
            }
        },
        _ = tick.tick() => {
          if dirty {
            for alpha in pixels.iter_mut().skip(3).step_by(4) { *alpha = 255; }
            sink.add(ScreenFrame { width: width as u32, height: height as u32,
              pixels: pixels.clone(), detail: String::new(), close_code: 0 }).map_err(|_| anyhow!("Viewer closed"))?;
            dirty = false;
          }
          client.input(X11Event::Refresh).await?;
        }
      }
    }
  }.await;
    let _ = client.close().await;
    network.abort();
    outcome
}
