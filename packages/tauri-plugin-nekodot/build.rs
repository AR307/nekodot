fn main() {
    tauri_plugin::Builder::new(&[
        "push_token",
        "clear_push_token",
        "focus_conversation",
        "take_notification",
        "share_file",
        "background",
        "register_listener",
        "remove_listener",
    ])
    .android_path("android")
    .build();
}
