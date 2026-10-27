use godot::builtin::ColorChannelOrder;
use godot::classes::web_socket_peer::State as SocketState;
use godot::classes::{INode, Node, Time, WebSocketPeer};
use godot::prelude::*;
use webgame_client::{Command, HELP, State};
use webgame_protocol::{
    Appearance, ClientMessage, Facing, GameAction, LobbyCode, MAX_COORD, Movement,
    PROTOCOL_VERSION, PlayerSlot, ServerMessage, decode, encode,
};

/// The connection to the game server. Add one to the scene tree (the Session autoload does)
/// and it talks to the server on its own, emitting signals as things happen.
///
/// Everything sent and received uses the `webgame-protocol` types, so the game and the server
/// can't disagree about a message. What the player knows (their role, who is alive, the phase)
/// is kept in the same `State` the terminal client uses, and so is the text shown for each
/// event, so both clients describe the game the same way.
///
/// It uses Godot's WebSocketPeer, which works in the web export as well as on desktop.
#[derive(GodotClass)]
#[class(base=Node)]
pub struct GameClient {
    base: Base<Node>,
    socket: Option<Gd<WebSocketPeer>>,
    /// Messages asked for before the socket opened, sent in order once it does. The first is
    /// always the hello.
    pending: Vec<ClientMessage>,
    open: bool,
    state: State,
    /// The last movement sent, so standing still sends nothing.
    sent_movement: Option<Movement>,
}

#[godot_api]
impl INode for GameClient {
    fn init(base: Base<Node>) -> Self {
        GameClient {
            base,
            socket: None,
            pending: Vec::new(),
            open: false,
            state: State::default(),
            sent_movement: None,
        }
    }

    fn process(&mut self, _delta: f64) {
        self.poll();
    }
}

#[godot_api]
impl GameClient {
    /// The server said hello back: the player is identified and can create or join a lobby.
    #[signal]
    fn connected();

    /// The connection closed or couldn't be made. `reason` says why, for showing the player.
    #[signal]
    fn disconnected(reason: GString);

    /// Who is in the lobby, or who is alive in the game, changed. Read `members()`.
    #[signal]
    fn members_changed();

    /// The game moved to a new phase (or the lobby closed). Read `phase_label()`.
    #[signal]
    fn phase_changed();

    /// A line of text for the game log: chat, private night results, deaths, votes.
    #[signal]
    fn log_line(text: GString);

    /// The server refused something, for example joining a lobby that doesn't exist.
    #[signal]
    fn server_error(message: GString);

    /// Another player's character moved. `facing` is a `Character.Facing` value.
    #[signal]
    fn player_moved(lot: i64, position: Vector2, facing: i64, walking: bool);

    /// What the player can do changed (a new phase, a vote counted, a choice confirmed).
    /// Read `actions()`.
    #[signal]
    fn actions_changed();

    /// Opens a connection to `url` (like `ws://127.0.0.1:9090/ws`) as `username`. Returns ""
    /// when the connection is under way, or a message saying why it couldn't start. Anything
    /// asked for before the server answers is sent once it does.
    #[func]
    fn connect_to_server(&mut self, url: GString, username: GString) -> GString {
        self.disconnect_from_server();
        let mut socket = WebSocketPeer::new_gd();
        let error = socket.connect_to_url(&url);
        if error != godot::global::Error::OK {
            return text(format!("Couldn't connect to {url}: {error:?}"));
        }
        self.socket = Some(socket);
        self.pending = vec![ClientMessage::Hello {
            version: PROTOCOL_VERSION,
            username: username.to_string(),
        }];
        GString::new()
    }

    /// Closes the connection, if there is one, and forgets the lobby and game.
    #[func]
    fn disconnect_from_server(&mut self) {
        if let Some(mut socket) = self.socket.take() {
            socket.close();
        }
        self.open = false;
        self.pending.clear();
        self.state = State::default();
        self.sent_movement = None;
    }

    /// Whether the server has accepted this player's hello.
    #[func]
    fn is_online(&self) -> bool {
        self.open && self.state.user_id.is_some()
    }

    #[func]
    fn create_lobby(&mut self) {
        self.send(ClientMessage::CreateLobby);
    }

    /// Asks to join a lobby. Returns "" when the code is well formed and the request was sent,
    /// or a message saying what's wrong with the code. The server can still refuse, with
    /// `server_error`.
    #[func]
    fn join_lobby(&mut self, code: GString) -> GString {
        match LobbyCode::parse(&code.to_string()) {
            Ok(code) => {
                self.send(ClientMessage::JoinLobby { code });
                GString::new()
            }
            Err(err) => text(capitalize(&err.to_string())),
        }
    }

    #[func]
    fn leave_lobby(&mut self) {
        self.send(ClientMessage::LeaveLobby);
    }

    #[func]
    fn start_game(&mut self) {
        self.send(ClientMessage::StartGame);
    }

    /// Tells everyone where this player's character is. Call it every frame or on a timer;
    /// only changes are sent. `facing` is a `Character.Facing` value.
    #[func]
    fn send_movement(&mut self, position: Vector2, facing: i64, walking: bool) {
        if self.state.lobby.is_none() {
            return;
        }
        let coord = |value: f32| (value.round() as i32).clamp(0, MAX_COORD);
        let movement = Movement {
            x: coord(position.x),
            y: coord(position.y),
            facing: u8::try_from(facing)
                .ok()
                .and_then(Facing::from_index)
                .unwrap_or_default(),
            walking,
        };
        if self.sent_movement != Some(movement) {
            self.sent_movement = Some(movement);
            self.send(ClientMessage::Move(movement));
        }
    }

    /// Tells everyone how this player's character and house look: the fields of a
    /// `CharacterAppearance`, with `items` mapping slot names to item names, and `house` mapping
    /// the house layers the player picked to their styles.
    #[func]
    fn set_appearance(
        &mut self,
        body_type: GString,
        gender: GString,
        skin_color: Color,
        items: VarDictionary,
        house: VarDictionary,
    ) {
        self.send(ClientMessage::SetAppearance(Appearance {
            body_type: body_type.to_string(),
            gender: gender.to_string(),
            skin_color: skin_color.to_u32(ColorChannelOrder::RGBA),
            items: sorted_pairs(&items),
            house: sorted_pairs(&house),
        }));
    }

    /// Where everyone else's character last was, one Dictionary each: `lot`, `position`
    /// (Vector2), `facing` and `walking`. For placing players when the town opens; after that,
    /// `player_moved` reports each move.
    #[func]
    fn positions(&self) -> Array<VarDictionary> {
        self.state
            .positions
            .iter()
            .map(|(slot, movement)| {
                vdict! {
                    "lot" => i64::from(slot.0),
                    "position" => position(movement),
                    "facing" => i64::from(movement.facing.index()),
                    "walking" => movement.walking,
                }
            })
            .collect()
    }

    /// What the player can do right now, as buttons, one Dictionary each: `label`, `command`
    /// (pass it to `submit` when pressed), `lot` (the player it is aimed at, or -1 for a button
    /// that stands alone) and `selected` (whether it is the current choice).
    #[func]
    fn actions(&self) -> Array<VarDictionary> {
        self.state
            .actions()
            .into_iter()
            .map(|action| {
                vdict! {
                    "label" => &text(&action.label),
                    "command" => &text(&action.command),
                    "lot" => action.target.map_or(-1, |slot| i64::from(slot.0)),
                    "selected" => action.selected,
                }
            })
            .collect()
    }

    /// Replaces the player's last will, which everyone reads when they die. Unlike `/will`,
    /// this can also clear it.
    #[func]
    fn set_last_will(&mut self, will: GString) {
        self.state.will = will.to_string();
        self.send(ClientMessage::Game(GameAction::SetLastWill(
            will.to_string(),
        )));
    }

    /// The player's last will as they last set it.
    #[func]
    fn last_will(&self) -> GString {
        text(&self.state.will)
    }

    /// Handles a line the player typed, exactly like the terminal client: plain text is chat
    /// on whatever channel they can use now, and `/vote 3`, `/target 2`, `/will ...` and the
    /// rest are actions. Returns "" when it was sent, or a message saying what was wrong.
    /// Commands that only show information (`/help`, `/role`) come back through `log_line`.
    #[func]
    fn submit(&mut self, line: GString) -> GString {
        let command = match webgame_client::parse(&line.to_string(), &self.state) {
            Ok(command) => command,
            Err(err) => return text(err),
        };
        let text = match command {
            Command::Send(message) => {
                if let ClientMessage::Game(GameAction::SetLastWill(will)) = &message {
                    self.state.will = will.clone();
                }
                self.send(message);
                return GString::new();
            }
            Command::Players => self.state.players_text(),
            Command::Role => self.state.role_text(),
            Command::Roles => self.state.roles_text(),
            Command::CopyFrom(slot) => {
                let line = self.state.copy_from(slot);
                self.signals().actions_changed().emit();
                line
            }
            Command::Help => HELP.to_string(),
            Command::Quit => {
                self.leave_lobby();
                return GString::new();
            }
        };
        self.signals().log_line().emit(&GString::from(&text));
        GString::new()
    }

    /// The lobby code, or "" when not in a lobby.
    #[func]
    fn lobby_code(&self) -> GString {
        self.state
            .lobby
            .as_ref()
            .map(|lobby| GString::from(lobby.code.as_str()))
            .unwrap_or_default()
    }

    #[func]
    fn is_host(&self) -> bool {
        match (&self.state.lobby, self.state.user_id) {
            (Some(lobby), Some(me)) => lobby.host == me,
            _ => false,
        }
    }

    /// Whether a game is being played (not in the lobby, not over).
    #[func]
    fn in_game(&self) -> bool {
        self.state.in_game()
    }

    /// This player's lot, from 0, or -1 when they don't have one.
    #[func]
    fn my_lot(&self) -> i32 {
        let Some(me) = self.state.user_id else {
            return -1;
        };
        self.state
            .lobby
            .as_ref()
            .and_then(|lobby| lobby.members.iter().find(|m| m.user_id == me))
            .map(|member| i32::from(member.slot.0))
            .unwrap_or(-1)
    }

    /// Everyone in the lobby, one Dictionary each, in lot order:
    /// `lot` (int, from 0), `number` (int, the number players type, from 1), `name`,
    /// `user_id` (String, stable for a username), `connected`, `alive` (always true outside a
    /// game), `is_host`, `is_me`, and `appearance`: a Dictionary with the fields of a
    /// `CharacterAppearance` plus `house` (picked house layers to styles), or null until their
    /// client sends it.
    #[func]
    fn members(&self) -> Array<VarDictionary> {
        let mut out = Array::new();
        let Some(lobby) = &self.state.lobby else {
            return out;
        };
        let mut members = lobby.members.clone();
        members.sort_by_key(|m| m.slot);
        for member in members {
            let alive = self
                .state
                .players
                .iter()
                .find(|p| p.slot == member.slot)
                .is_none_or(|p| p.alive);
            out.push(&vdict! {
                "lot" => i64::from(member.slot.0),
                "number" => i64::from(member.slot.0) + 1,
                "name" => &GString::from(&member.name),
                "user_id" => &text(member.user_id.0.to_string()),
                "connected" => member.connected,
                "alive" => alive,
                "is_host" => member.user_id == lobby.host,
                "is_me" => Some(member.user_id) == self.state.user_id,
                "appearance" => &member
                    .appearance
                    .as_ref()
                    .map_or(Variant::nil(), |look| appearance(look).to_variant()),
            });
        }
        out
    }

    /// The phase and the time left in it, like "Day 1 Voting, 3 trials left 0:42".
    #[func]
    fn phase_label(&self) -> GString {
        let now = (Time::singleton().get_unix_time_from_system() * 1000.0) as u64;
        text(self.state.clock(now))
    }

    /// Whether it is night, for dimming the town.
    #[func]
    fn is_night(&self) -> bool {
        self.state.phase.is_night()
    }

    /// The player's role, like "Sheriff", or "" before a game starts.
    #[func]
    fn role_name(&self) -> GString {
        self.state
            .role
            .map(|role| GString::from(role.name()))
            .unwrap_or_default()
    }

    /// Every command `submit` understands, one per line.
    #[func]
    fn help_text(&self) -> GString {
        HELP.into()
    }
}

impl GameClient {
    fn send(&mut self, message: ClientMessage) {
        match (&mut self.socket, self.open) {
            (Some(socket), true) => {
                socket.send(&PackedByteArray::from(encode(&message).as_slice()));
            }
            _ => self.pending.push(message),
        }
    }

    fn poll(&mut self) {
        let Some(socket) = &mut self.socket else {
            return;
        };
        socket.poll();
        let ready = socket.get_ready_state();
        if ready == SocketState::OPEN && !self.open {
            self.open = true;
            for message in std::mem::take(&mut self.pending) {
                self.send(message);
            }
        }
        let mut received = Vec::new();
        if let Some(socket) = &mut self.socket {
            while socket.get_available_packet_count() > 0 {
                let packet = socket.get_packet();
                if socket.was_string_packet() {
                    continue;
                }
                match decode::<ServerMessage>(packet.as_slice()) {
                    Ok(message) => received.push(message),
                    Err(err) => {
                        godot_error!("GameClient: unreadable message: {err}");
                    }
                }
            }
        }
        for message in received {
            self.receive(message);
        }
        if ready == SocketState::CLOSED {
            let reason = match &self.socket {
                Some(socket) if self.open => {
                    let reason = socket.get_close_reason().to_string();
                    if reason.is_empty() {
                        "The server closed the connection.".to_string()
                    } else {
                        reason
                    }
                }
                _ => "Couldn't reach the server. Is it running?".to_string(),
            };
            self.disconnect_from_server();
            self.signals().members_changed().emit();
            self.signals().disconnected().emit(&GString::from(&reason));
        }
    }

    fn receive(&mut self, message: ServerMessage) {
        if let ServerMessage::Moved { slot, movement } = message {
            self.state.positions.insert(slot, movement);
            self.signals().player_moved().emit(
                i64::from(slot.0),
                position(&movement),
                i64::from(movement.facing.index()),
                movement.walking,
            );
            return;
        }
        if matches!(message, ServerMessage::Lobby(_)) && self.my_slot().is_none() {
            // A new lobby: send this player's position again so the others see them.
            self.sent_movement = None;
        }
        let welcome = matches!(message, ServerMessage::Welcome { .. });
        let members = matches!(
            message,
            ServerMessage::Lobby(_)
                | ServerMessage::LeftLobby
                | ServerMessage::GameStarted(_)
                | ServerMessage::Deaths(_)
                | ServerMessage::GameOver(_)
        );
        let phase = matches!(
            message,
            ServerMessage::Phase { .. } | ServerMessage::GameOver(_) | ServerMessage::LeftLobby
        );
        let error = match &message {
            ServerMessage::Error(err) => Some(err.message.clone()),
            _ => None,
        };
        let before = self.state.phase.clone();
        let lines = self.state.apply(message);
        if welcome {
            self.signals().connected().emit();
        }
        if let Some(error) = error {
            self.signals().server_error().emit(&GString::from(&error));
        }
        for line in lines {
            self.signals().log_line().emit(&GString::from(&line));
        }
        if members {
            self.signals().members_changed().emit();
        }
        if phase || before != self.state.phase {
            self.signals().phase_changed().emit();
        }
        self.signals().actions_changed().emit();
    }

    fn my_slot(&self) -> Option<PlayerSlot> {
        let me = self.state.user_id?;
        let lobby = self.state.lobby.as_ref()?;
        lobby
            .members
            .iter()
            .find(|m| m.user_id == me)
            .map(|m| m.slot)
    }
}

fn position(movement: &Movement) -> Vector2 {
    Vector2::new(movement.x as f32, movement.y as f32)
}

fn appearance(appearance: &Appearance) -> VarDictionary {
    let [r, g, b, a] = appearance.skin_color.to_be_bytes();
    vdict! {
        "body_type" => &text(&appearance.body_type),
        "gender" => &text(&appearance.gender),
        "skin_color" => Color::from_rgba8(r, g, b, a),
        "items" => &dictionary(&appearance.items),
        "house" => &dictionary(&appearance.house),
    }
}

/// A Godot Dictionary of name pairs, like slot to item.
fn dictionary(pairs: &[(String, String)]) -> VarDictionary {
    pairs
        .iter()
        .map(|(key, value)| (text(key).to_variant(), text(value).to_variant()))
        .collect()
}

/// The entries of a Godot Dictionary as text pairs, sorted so the same choices always make the
/// same message.
fn sorted_pairs(dictionary: &VarDictionary) -> Vec<(String, String)> {
    let mut pairs: Vec<(String, String)> = dictionary
        .iter_shared()
        .map(|(key, value)| (key.to_string(), value.to_string()))
        .collect();
    pairs.sort();
    pairs
}

/// Converts Rust text for Godot.
fn text(value: impl AsRef<str>) -> GString {
    GString::from(value.as_ref())
}

fn capitalize(text: &str) -> String {
    let mut chars = text.chars();
    match chars.next() {
        Some(first) => first.to_uppercase().chain(chars).collect::<String>() + ".",
        None => String::new(),
    }
}
