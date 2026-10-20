//! Turns a typed line into what to do with it. Players are named by their lot number, 1 to 15,
//! the same number `/players` prints.

use webgame_protocol::{
    ChatChannel, ClientMessage, GameAction, LobbyCode, NightAction, PlayerSlot, Verdict,
};

use crate::state::State;

/// What a typed line asks for.
#[derive(Debug, PartialEq)]
pub enum Command {
    /// Something to send to the server.
    Send(ClientMessage),
    /// Print the players.
    Players,
    /// Print your role, its goal, and your team.
    Role,
    /// Print the role list for this game.
    Roles,
    Help,
    Quit,
}

pub const HELP: &str = "\
Lobby:   /create   /join CODE   /leave   /start (host)   /players
Chat:    type a line to talk (town square by day; jail, Mafia or dead chat by night)
         /w N text        whisper to player N during the day
Day:     /vote N   /unvote   /guilty   /inno   /abstain
         /jail N          (Jailer) pick tonight's prisoner, /jail to clear
Night:   /target N        use your ability on player N (Lookout, Doctor, Mafioso, haunt ...)
         /target N M      Copycat: use N's ability on M. Disguiser: swap with N (M is ignored)
         /alert /vest /ignite /execute   abilities with no target
         /cancel          take back tonight's action
Notes:   /will text       set your last will (shown when you die), /will to see it
Info:    /role   /roles   /players   /help   /quit";

/// Parses one line of input. Plain text is chat; lines starting with `/` are commands.
pub fn parse(line: &str, state: &State) -> Result<Command, String> {
    let line = line.trim();
    let Some(rest) = line.strip_prefix('/') else {
        return chat(line, state);
    };
    let (word, args) = rest.split_once(' ').unwrap_or((rest, ""));
    let args = args.trim();
    let game = |action: GameAction| Ok(Command::Send(ClientMessage::Game(action)));
    let night = |action: Option<NightAction>| game(GameAction::Night(action));
    match word.to_ascii_lowercase().as_str() {
        "help" | "h" | "?" => Ok(Command::Help),
        "quit" | "exit" | "q" => Ok(Command::Quit),
        "players" | "p" => Ok(Command::Players),
        "role" => Ok(Command::Role),
        "roles" => Ok(Command::Roles),
        "create" => Ok(Command::Send(ClientMessage::CreateLobby)),
        "join" => LobbyCode::parse(args)
            .map(|code| Command::Send(ClientMessage::JoinLobby { code }))
            .map_err(|err| err.to_string()),
        "leave" => Ok(Command::Send(ClientMessage::LeaveLobby)),
        "start" => Ok(Command::Send(ClientMessage::StartGame)),
        "w" | "whisper" => {
            let (who, text) = args.split_once(' ').ok_or("Usage: /w N text")?;
            Ok(Command::Send(ClientMessage::Chat {
                channel: ChatChannel::Whisper { to: slot(who)? },
                text: text.trim().to_string(),
            }))
        }
        "vote" => game(GameAction::Vote(Some(slot(args)?))),
        "unvote" => game(GameAction::Vote(None)),
        "guilty" | "g" => game(GameAction::Judgement(Verdict::Guilty)),
        "inno" | "innocent" | "i" => game(GameAction::Judgement(Verdict::Innocent)),
        "abstain" => game(GameAction::Judgement(Verdict::Abstain)),
        "jail" if args.is_empty() => game(GameAction::Jail(None)),
        "jail" => game(GameAction::Jail(Some(slot(args)?))),
        "target" | "t" => {
            let mut numbers = args.split_whitespace();
            let first = slot(numbers.next().ok_or("Usage: /target N [M]")?)?;
            match numbers.next() {
                Some(second) => night(Some(NightAction::TwoTargets(first, slot(second)?))),
                None => night(Some(NightAction::Target(first))),
            }
        }
        "alert" | "vest" | "ignite" | "execute" => night(Some(NightAction::Activate)),
        "cancel" => night(None),
        "will" if args.is_empty() => Ok(Command::Role),
        "will" => game(GameAction::SetLastWill(args.replace("\\n", "\n"))),
        _ => Err(format!("Unknown command /{word}. Type /help.")),
    }
}

/// Plain text goes to whichever channel this player can talk in right now.
fn chat(text: &str, state: &State) -> Result<Command, String> {
    if text.is_empty() {
        return Err(String::new());
    }
    let channel = if state.in_game() {
        state
            .chat_context()
            .and_then(|context| context.default_channel())
            .ok_or("Nobody can hear you right now.")?
    } else if state.lobby.is_some() {
        ChatChannel::Lobby
    } else {
        return Err("Join a lobby first: /create or /join CODE.".into());
    };
    Ok(Command::Send(ClientMessage::Chat {
        channel,
        text: text.to_string(),
    }))
}

fn slot(number: &str) -> Result<PlayerSlot, String> {
    number
        .trim()
        .parse()
        .ok()
        .and_then(PlayerSlot::from_number)
        .ok_or_else(|| format!("`{number}` isn't a player number. Type /players."))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn send(line: &str) -> ClientMessage {
        match parse(line, &State::default()) {
            Ok(Command::Send(message)) => message,
            other => panic!("{line} parsed as {other:?}"),
        }
    }

    #[test]
    fn players_are_numbered_from_one() {
        assert_eq!(
            send("/vote 3"),
            ClientMessage::Game(GameAction::Vote(Some(PlayerSlot(2))))
        );
        assert_eq!(
            send("/target 1 15"),
            ClientMessage::Game(GameAction::Night(Some(NightAction::TwoTargets(
                PlayerSlot(0),
                PlayerSlot(14)
            ))))
        );
        assert!(parse("/vote 0", &State::default()).is_err());
        assert!(parse("/vote 16", &State::default()).is_err());
    }

    #[test]
    fn whispers_keep_their_text() {
        assert_eq!(
            send("/w 2 meet me  at the well"),
            ClientMessage::Chat {
                channel: ChatChannel::Whisper { to: PlayerSlot(1) },
                text: "meet me  at the well".into()
            }
        );
    }

    #[test]
    fn plain_text_needs_a_lobby() {
        assert!(parse("hello", &State::default()).is_err());
    }

    #[test]
    fn wills_can_have_line_breaks() {
        assert_eq!(
            send("/will N1: checked 3\\nN2: 3 visited 5"),
            ClientMessage::Game(GameAction::SetLastWill(
                "N1: checked 3\nN2: 3 visited 5".into()
            ))
        );
    }
}
