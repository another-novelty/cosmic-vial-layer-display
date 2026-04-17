use cosmic::{
    app::{Core, Task},
    iced::{self, Subscription},
    widget::{self, menu},
    Application, Element,
};
use hidapi::HidApi;
use serde::Deserialize;
use std::{collections::HashMap, path::PathBuf, time::Duration};

const APP_ID: &str = "de.faabe.vial-layer";
const VIAL_USAGE_PAGE: u16 = 0xFF60;
const VIAL_USAGE: u16 = 0x61;
const LAYER_QUERY_CMD: u8 = 0x42;

#[derive(Debug, Deserialize, Default)]
struct Config {
    #[serde(default)]
    layers: Vec<String>,
}

impl Config {
    fn load() -> Self {
        let path = config_path();
        let src = std::fs::read_to_string(&path).unwrap_or_default();
        toml::from_str(&src).unwrap_or_else(|e| {
            eprintln!("vial-layer: error in {}: {e}", path.display());
            Self::default()
        })
    }

    fn label_for(&self, layer: u8) -> String {
        self.layers
            .get(layer as usize)
            .filter(|s| !s.is_empty())
            .cloned()
            .unwrap_or_else(|| format!("Layer {layer}"))
    }
}

fn config_path() -> PathBuf {
    if let Ok(p) = std::env::var("VIAL_LAYER_CONFIG") {
        return PathBuf::from(p);
    }
    let base = std::env::var("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(".config"));
    base.join("vial-layer").join("config.toml")
}

#[derive(Debug, Clone)]
enum Message {
    Layer(Option<u8>),
    TogglePause,
    ReloadConfig,
    Surface(cosmic::surface::Action),
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ContextMenuAction {
    TogglePause,
    ReloadConfig,
}

impl menu::Action for ContextMenuAction {
    type Message = Message;
    fn message(&self) -> Message {
        match self {
            ContextMenuAction::TogglePause => Message::TogglePause,
            ContextMenuAction::ReloadConfig => Message::ReloadConfig,
        }
    }
}

struct LayerApplet {
    core: Core,
    config: Config,
    layer: Option<u8>,
    vid: u16,
    pid: u16,
    paused: bool,
}

impl Application for LayerApplet {
    type Executor = cosmic::executor::Default;
    type Flags = ();
    type Message = Message;
    const APP_ID: &'static str = APP_ID;

    fn core(&self) -> &Core {
        &self.core
    }
    fn core_mut(&mut self) -> &mut Core {
        &mut self.core
    }

    fn init(core: Core, _flags: ()) -> (Self, Task<Message>) {
        let vid = parse_hex_env("KBD_VID");
        let pid = parse_hex_env("KBD_PID");
        let config = Config::load();
        (Self { core, config, layer: None, vid, pid, paused: false }, Task::none())
    }

    fn update(&mut self, message: Message) -> Task<Message> {
        match message {
            Message::Layer(l) => self.layer = l,
            Message::TogglePause => self.paused = !self.paused,
            Message::ReloadConfig => self.config = Config::load(),
            Message::Surface(action) => {
                return cosmic::task::message(cosmic::Action::Cosmic(
                    cosmic::app::Action::Surface(action),
                ));
            }
        }
        Task::none()
    }

    fn view(&self) -> Element<'_, Message> {
        let label = match self.layer {
            None if self.paused => "paused".to_string(),
            None => "disconnected".to_string(),
            Some(0xFF) => "no firmware support".to_string(),
            Some(l) => self.config.label_for(l),
        };

        let menu_items = Some(menu::items(
            &HashMap::new(),
            vec![
                menu::Item::CheckBox(
                    "Pause polling",
                    None,
                    self.paused,
                    ContextMenuAction::TogglePause,
                ),
                menu::Item::Divider,
                menu::Item::Button("Reload config", None, ContextMenuAction::ReloadConfig),
            ],
        ));

        let content = widget::container(widget::text(label).size(13))
            .align_y(iced::Alignment::Center)
            .height(iced::Length::Fill);

        widget::context_menu(content, menu_items)
            .on_surface_action(Message::Surface)
            .into()
    }

    fn subscription(&self) -> Subscription<Message> {
        if self.paused {
            return Subscription::none();
        }
        iced::time::every(Duration::from_millis(100))
            .with((self.vid, self.pid))
            .map(|((vid, pid), _)| Message::Layer(query_layer(vid, pid)))
    }
}

fn parse_hex_env(var: &str) -> u16 {
    std::env::var(var)
        .ok()
        .and_then(|s| u16::from_str_radix(s.trim_start_matches("0x"), 16).ok())
        .unwrap_or(0)
}

fn vial_is_running() -> bool {
    let Ok(procs) = std::fs::read_dir("/proc") else { return false };
    procs.filter_map(|e| e.ok()).any(|e| {
        std::fs::read_to_string(e.path().join("cmdline"))
            .map_or(false, |s| s.contains("vial"))
    })
}

fn query_layer(vid: u16, pid: u16) -> Option<u8> {
    if vid == 0 || pid == 0 {
        return None;
    }
    if vial_is_running() {
        return None;
    }
    let api = HidApi::new().ok()?;
    let device_info = api.device_list().find(|d| {
        d.vendor_id() == vid
            && d.product_id() == pid
            && d.usage_page() == VIAL_USAGE_PAGE
            && d.usage() == VIAL_USAGE
    })?;
    let device = device_info.open_device(&api).ok()?;

    let mut buf = [0u8; 33];
    buf[1] = LAYER_QUERY_CMD;
    device.write(&buf).ok()?;

    let mut resp = [0u8; 32];
    device.read_timeout(&mut resp, 20).ok()?;
    Some(resp[0])
}

fn main() -> cosmic::iced::Result {
    cosmic::applet::run::<LayerApplet>(())
}
