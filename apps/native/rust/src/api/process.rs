use crate::frb_generated::StreamSink;
use anyhow::{anyhow, Result};
use std::{
    collections::HashMap,
    io::{BufRead, BufReader, Read, Write},
    process::{ChildStdin, Command, Stdio},
    sync::{Mutex, OnceLock},
    thread,
};

/// One line of output, or the final exit of an owned process.
#[derive(Clone)]
pub struct OwnedEvent {
    /// 1 stdout line, 2 stderr line, 3 exited (`code`), 4 could not start (`text`).
    pub kind: u8,
    pub text: String,
    pub code: i32,
}

#[cfg(windows)]
use std::sync::Arc;

struct Owned {
    stdin: Option<ChildStdin>,
    pid: u32,
    #[cfg(windows)]
    job: Arc<crate::job::Job>,
}

static OWNED: OnceLock<Mutex<HashMap<String, Owned>>> = OnceLock::new();
fn owned() -> &'static Mutex<HashMap<String, Owned>> {
    OWNED.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Starts a child without a console window that cannot outlive this app: on Windows its
/// whole tree runs in a kill-on-close job; on POSIX it leads its own process group.
/// The environment is exactly `env` (`KEY=VALUE`), not inherited.
pub fn owned_process_run(
    id: String,
    program: String,
    args: Vec<String>,
    cwd: String,
    env: Vec<String>,
    sink: StreamSink<OwnedEvent>,
) -> Result<()> {
    let mut command = Command::new(&program);
    command
        .args(&args)
        .current_dir(&cwd)
        .env_clear()
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    for entry in &env {
        let (key, value) = entry
            .split_once('=')
            .ok_or_else(|| anyhow!("Invalid environment entry"))?;
        command.env(key, value);
    }
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        command.creation_flags(CREATE_NO_WINDOW);
    }
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        command.process_group(0);
    }
    #[cfg(windows)]
    let job = Arc::new(crate::job::Job::new()?);
    let mut child = match command.spawn() {
        Ok(child) => child,
        Err(error) => {
            let _ = sink.add(OwnedEvent { kind: 4, text: format!("{program}: {error}"), code: -1 });
            return Ok(());
        }
    };
    #[cfg(windows)]
    {
        use std::os::windows::io::AsRawHandle;
        if let Err(error) = job.assign(child.as_raw_handle()) {
            let _ = child.kill();
            let _ = child.wait();
            let _ = sink.add(OwnedEvent { kind: 4, text: error.to_string(), code: -1 });
            return Ok(());
        }
    }
    let stdout = child.stdout.take().ok_or_else(|| anyhow!("No stdout"))?;
    let stderr = child.stderr.take().ok_or_else(|| anyhow!("No stderr"))?;
    owned().lock().unwrap().insert(
        id.clone(),
        Owned {
            stdin: child.stdin.take(),
            pid: child.id(),
            #[cfg(windows)]
            job: job.clone(),
        },
    );
    let readers = [
        forward(stdout, 1, sink.clone()),
        forward(stderr, 2, sink.clone()),
    ];
    thread::spawn(move || {
        let status = child.wait();
        for reader in readers {
            let _ = reader.join();
        }
        owned().lock().unwrap().remove(&id);
        // Dropping the last job handle reaps anything the child left running.
        #[cfg(windows)]
        drop(job);
        let code = match status {
            Ok(status) => status.code().unwrap_or(-1),
            Err(_) => -1,
        };
        let _ = sink.add(OwnedEvent { kind: 3, text: String::new(), code });
    });
    Ok(())
}

fn forward(
    stream: impl Read + Send + 'static,
    kind: u8,
    sink: StreamSink<OwnedEvent>,
) -> thread::JoinHandle<()> {
    thread::spawn(move || {
        let mut reader = BufReader::new(stream);
        let mut line = Vec::new();
        while matches!(reader.read_until(b'\n', &mut line), Ok(n) if n > 0) {
            let text = String::from_utf8_lossy(&line).trim_end_matches(['\r', '\n']).to_string();
            if sink.add(OwnedEvent { kind, text, code: 0 }).is_err() {
                break;
            }
            line.clear();
        }
    })
}

/// Writes to the child's stdin; `close` ends it, which the desktop Node treats as a stop.
#[flutter_rust_bridge::frb(sync)]
pub fn owned_process_write(id: String, data: String, close: bool) -> Result<()> {
    let mut map = owned().lock().unwrap();
    let process = map.get_mut(&id).ok_or_else(|| anyhow!("Process is not running"))?;
    if let Some(stdin) = process.stdin.as_mut() {
        stdin.write_all(data.as_bytes())?;
        stdin.flush()?;
    }
    if close {
        process.stdin = None;
    }
    Ok(())
}

/// Ends the whole owned tree immediately.
#[flutter_rust_bridge::frb(sync)]
pub fn owned_process_kill(id: String) -> Result<()> {
    let map = owned().lock().unwrap();
    let process = map.get(&id).ok_or_else(|| anyhow!("Process is not running"))?;
    #[cfg(windows)]
    process.job.terminate();
    #[cfg(unix)]
    unsafe {
        libc::killpg(process.pid as libc::pid_t, libc::SIGKILL);
    }
    let _ = process.pid;
    Ok(())
}
