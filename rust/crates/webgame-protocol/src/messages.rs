//! The wire contract: every message a client can send and every message the server can send.
//! Both are encoded with postcard and sent as WebSocket binary frames.

use std::fmt;

use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};

use crate::{
    Appearance, ChatChannel, ChatMessage, FightView, GamePhase, LobbyCode, Minigame, MinigamePlay,
    MinigameResult, Movement, NightAction, PlayerSlot, Role, RoleSlot, UserId, Verdict,
};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum ClientMessage {
    /// Must be the first message on a connection.
    Hello {
        version: u32,
        username: String,
    },
    CreateLobby,
    JoinLobby {
        code: LobbyCode,
    },
    LeaveLobby,
    /// Host only: start a game with everyone in the lobby.
    StartGame,
    Chat {
        channel: ChatChannel,
        text: String,
    },
    Game(GameAction),
    /// Where this player's character is now in the town. Sent a few times a second while it
    /// moves; the server passes it on to everyone else in the lobby.
    Move(Movement),
    /// How this player's character looks. Sent after joining a lobby.
    SetAppearance(Appearance),
}

/// Things a player does in a running game, other than chatting.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum GameAction {
    /// Replaces the player's last will, which everyone sees when they die.
    SetLastWill(String),
    /// During voting: vote to put someone on trial, or take the vote back.
    Vote(Option<PlayerSlot>),
    /// During a trial's judgement.
    Judgement(Verdict),
    /// Jailer only, by day: who to jail tonight, or nobody.
    Jail(Option<PlayerSlot>),
    /// At night, while choosing: the night action, or none. The last one sent is used.
    Night(Option<NightAction>),
    /// At night: a move in this player's current minigame.
    Minigame(MinigamePlay),
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum ServerMessage {
    Welcome {
        user_id: UserId,
        username: String,
    },
    Error(ServerError),
    /// The lobby as it is now. Sent on joining and whenever it changes.
    Lobby(LobbyInfo),
    LeftLobby,
    /// Sent to each player when a game starts, and again on reconnecting to one.
    GameStarted(GameStart),
    Phase {
        phase: GamePhase,
        ends_at_ms: u64,
    },
    Chat(ChatMessage),
    /// Public: someone whispered to someone. Only the two of them get the text.
    Whispered {
        from: PlayerSlot,
        to: PlayerSlot,
    },
    /// Private results and events, usually at dawn.
    Notices(Vec<Notice>),
    /// Who died since the last report: in the night, or by lynching.
    Deaths(Vec<DeathReport>),
    /// The current day votes and how many put someone on trial.
    Votes {
        votes: Vec<VoteEntry>,
        needed: u8,
    },
    TrialResult {
        accused: PlayerSlot,
        votes: Vec<(PlayerSlot, Verdict)>,
        guilty: u8,
        innocent: u8,
        convicted: bool,
    },
    /// This player's role changed: an Amnesiac remembered, an Executioner became a Jester, or a
    /// Mafia member was promoted.
    RoleChanged {
        role: Role,
    },
    /// The Mafia's members, sent to the Mafia when it changes.
    Team(Vec<TeamMember>),
    /// Public: an Amnesiac remembered they were like this role.
    Remembered {
        role: Role,
    },
    /// An action was taken, to confirm it.
    Accepted(Accepted),
    GameOver(GameOverInfo),
    /// This player's minigame for the stage of the night that just began. It lasts until
    /// `ends_at_ms`, the end of the stage.
    Minigame {
        game: Minigame,
        ends_at_ms: u64,
    },
    /// The fight this player is in, sent to both fighters whenever it changes.
    Fight(FightView),
    /// This player's minigame is over. `rolled` says the server decided it at random, because
    /// this player or their opponent asked it to.
    MinigameOver {
        result: MinigameResult,
        rolled: bool,
    },
    /// Another player's character moved in the town. Also sent for everyone's last position on
    /// joining a lobby.
    Moved {
        slot: PlayerSlot,
        movement: Movement,
    },
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ServerError {
    pub code: ErrorCode,
    pub message: String,
}

impl ServerError {
    pub fn new(code: ErrorCode, message: impl Into<String>) -> Self {
        ServerError {
            code,
            message: message.into(),
        }
    }
}

impl fmt::Display for ServerError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.message)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum ErrorCode {
    BadMessage,
    VersionMismatch,
    NotIdentified,
    AlreadyIdentified,
    InvalidName,
    LobbyNotFound,
    LobbyFull,
    AlreadyInLobby,
    NotInLobby,
    GameInProgress,
    NotHost,
    NotEnoughPlayers,
    /// The action isn't possible in this phase or for this player.
    NotAllowedNow,
    InvalidTarget,
    NoUsesLeft,
    TooLong,
    /// The same user connected again somewhere else, so this connection was dropped.
    ConnectedElsewhere,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LobbyInfo {
    pub code: LobbyCode,
    pub host: UserId,
    pub members: Vec<LobbyMember>,
    /// Whether a game is being played (not over yet).
    pub in_game: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LobbyMember {
    pub user_id: UserId,
    pub name: String,
    pub slot: PlayerSlot,
    /// False while the player is disconnected from a running game, holding their seat.
    pub connected: bool,
    /// How the player's character looks, once their client has said.
    pub appearance: Option<Appearance>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlayerSummary {
    pub slot: PlayerSlot,
    pub name: String,
    pub alive: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct TeamMember {
    pub slot: PlayerSlot,
    pub role: Role,
    pub alive: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct GameStart {
    pub you: PlayerSlot,
    pub role: Role,
    pub players: Vec<PlayerSummary>,
    pub role_list: Vec<RoleSlot>,
    /// Fellow Mafia members, for a Mafia player; empty for everyone else.
    pub team: Vec<TeamMember>,
    /// The player an Executioner must get lynched.
    pub executioner_target: Option<PlayerSlot>,
    pub last_will: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct VoteEntry {
    pub voter: PlayerSlot,
    pub target: PlayerSlot,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct DeathReport {
    pub slot: PlayerSlot,
    pub role: Role,
    pub will: String,
    pub causes: Vec<DeathCause>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum DeathCause {
    Lynched,
    Mafia,
    SerialKiller,
    Arsonist,
    Vigilante,
    Veteran,
    Jailer,
    Bodyguard,
    Trap,
    Poison,
    Haunted,
    /// A Vigilante who shot a Town member.
    Guilt,
}

/// Why an attack didn't kill its target.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum SaveReason {
    Defense,
    Healed,
    Guarded,
    Trapped,
    Jailed,
}

/// Something only one player learns, usually at dawn.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum Notice {
    /// You were taken to jail for the night.
    Jailed,
    /// To the Jailer: tonight's prisoner.
    JailedSomeone {
        prisoner: PlayerSlot,
    },
    /// To the Jailer: you executed a Town member and can't execute again.
    LostExecutions,
    Roleblocked,
    RoleblockImmune,
    /// You were attacked and survived.
    Attacked {
        saved: SaveReason,
    },
    /// To a Doctor: the person you healed was attacked.
    TargetAttacked {
        target: PlayerSlot,
    },
    /// To a Trapper: your trap went off.
    TrapTriggered {
        target: PlayerSlot,
    },
    /// To a Veteran: you shot someone who visited you.
    ShotVisitor,
    Doused,
    /// You will die tomorrow night unless a Doctor heals you.
    Poisoned,
    PoisonCured,
    SheriffResult {
        target: PlayerSlot,
        suspicious: bool,
    },
    InvestigatorResult {
        target: PlayerSlot,
        roles: Vec<Role>,
    },
    ConsigliereResult {
        target: PlayerSlot,
        role: Role,
    },
    LookoutResult {
        target: PlayerSlot,
        visitors: Vec<PlayerSlot>,
    },
    TrackerResult {
        target: PlayerSlot,
        visited: Vec<PlayerSlot>,
    },
    SpyMafiaVisits {
        targets: Vec<PlayerSlot>,
    },
    /// What the Spy's bugged target experienced tonight.
    SpyBug {
        target: PlayerSlot,
        heard: Vec<Notice>,
    },
    /// To the Copycat: the role of the player copied, and whether its ability could be used.
    CopycatLearned {
        target: PlayerSlot,
        role: Role,
        copied: bool,
    },
    /// You visited a house where an Ambusher was waiting.
    SawAmbusher {
        ambusher: PlayerSlot,
    },
    /// To a lynched Jester: pick one of these to haunt tonight, or one is picked for you.
    ChooseHaunt {
        candidates: Vec<PlayerSlot>,
    },
}

/// Confirms an action so the client can show it.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum Accepted {
    LastWill,
    Verdict(Verdict),
    Jail(Option<PlayerSlot>),
    Night(Option<NightAction>),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum Outcome {
    Town,
    Mafia,
    /// A Neutral Killing role won alone.
    Solo(Role),
    Draw,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct GameOverInfo {
    pub outcome: Outcome,
    /// Everyone who won, alive or dead: the winning side plus any Neutral whose own goal was met.
    pub winners: Vec<PlayerSlot>,
    pub roles: Vec<(PlayerSlot, Role)>,
}

/// Encodes a message for the wire.
pub fn encode<T: Serialize>(message: &T) -> Vec<u8> {
    postcard::to_allocvec(message).expect("protocol messages always serialize")
}

#[derive(Debug)]
pub struct DecodeError(postcard::Error);

impl fmt::Display for DecodeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "couldn't decode message: {}", self.0)
    }
}

impl std::error::Error for DecodeError {}

/// Decodes a message from the wire.
pub fn decode<T: DeserializeOwned>(bytes: &[u8]) -> Result<T, DecodeError> {
    postcard::from_bytes(bytes).map_err(DecodeError)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{ChatSender, DayStage};

    fn round_trip<T: Serialize + DeserializeOwned + PartialEq + fmt::Debug>(message: T) {
        let bytes = encode(&message);
        assert_eq!(decode::<T>(&bytes).unwrap(), message);
    }

    #[test]
    fn client_messages_round_trip() {
        round_trip(ClientMessage::Hello {
            version: crate::PROTOCOL_VERSION,
            username: "Ada".into(),
        });
        round_trip(ClientMessage::JoinLobby {
            code: LobbyCode::parse("ABCDEF").unwrap(),
        });
        round_trip(ClientMessage::Game(GameAction::Night(Some(
            NightAction::TwoTargets(PlayerSlot(1), PlayerSlot(2)),
        ))));
        round_trip(ClientMessage::Game(GameAction::Minigame(
            MinigamePlay::Roll,
        )));
        round_trip(ClientMessage::Game(GameAction::Minigame(
            MinigamePlay::Move(crate::FightMove::Strike),
        )));
        round_trip(ClientMessage::Move(Movement {
            x: 320,
            y: 460,
            facing: crate::Facing::Left,
            walking: true,
        }));
        round_trip(ClientMessage::SetAppearance(Appearance {
            body_type: "regular".into(),
            gender: "female".into(),
            skin_color: 0xf5cbb0ff,
            items: vec![("hat".into(), "cowboy".into())],
            house: vec![("roof".into(), "victorian".into())],
        }));
    }

    #[test]
    fn server_messages_round_trip() {
        round_trip(ServerMessage::Phase {
            phase: GamePhase::Day {
                day: 2,
                stage: DayStage::Judgement {
                    accused: PlayerSlot(4),
                },
            },
            ends_at_ms: 1_234,
        });
        round_trip(ServerMessage::Chat(ChatMessage {
            channel: ChatChannel::Jail,
            from: ChatSender::Jailer,
            text: "why are you here".into(),
        }));
        round_trip(ServerMessage::Phase {
            phase: GamePhase::Night {
                night: 3,
                stage: crate::NightStage::Kill { round: 2 },
            },
            ends_at_ms: 9,
        });
        round_trip(ServerMessage::Minigame {
            game: Minigame::Fight { attacking: false },
            ends_at_ms: 5_000,
        });
        round_trip(ServerMessage::Fight(FightView {
            you: crate::Fighter {
                hp: 2,
                guarding: true,
                winding: None,
                staggered_ms: 0,
            },
            opponent: crate::Fighter {
                hp: 3,
                guarding: false,
                winding: Some((crate::FightMove::Grab, 120)),
                staggered_ms: 0,
            },
        }));
        round_trip(ServerMessage::MinigameOver {
            result: MinigameResult::Passed,
            rolled: true,
        });
        round_trip(ServerMessage::Notices(vec![Notice::SpyBug {
            target: PlayerSlot(3),
            heard: vec![Notice::Attacked {
                saved: SaveReason::Healed,
            }],
        }]));
    }

    #[test]
    fn a_bad_lobby_code_doesnt_decode() {
        let bytes = encode(&ClientMessage::Chat {
            channel: ChatChannel::Lobby,
            text: "x".into(),
        });
        assert!(decode::<ClientMessage>(&bytes).is_ok());
        // A JoinLobby whose code string is not a valid code is rejected while decoding.
        #[derive(Serialize)]
        enum Fake {
            _Hello,
            _Create,
            Join { code: String },
        }
        let bytes = encode(&Fake::Join {
            code: "nope".into(),
        });
        assert!(decode::<ClientMessage>(&bytes).is_err());
    }
}
