use tauri::{
    Runtime,
    plugin::{Builder, TauriPlugin},
};

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("nekodot")
        .setup(|_app, api| {
            #[cfg(target_os = "android")]
            api.register_android_plugin("app.nekodot.nativeclient", "NekodotPlugin")?;
            #[cfg(not(target_os = "android"))]
            let _ = api;
            Ok(())
        })
        .build()
}
