//! Canned game states for the style gallery (front/tools/gallery), so it can show the real HUD
//! in a lobby, by day, at night and so on without a server. Each fixture runs the real game
//! rules in-process (`webgame_game::Game`) from a fixed seed, advancing a virtual clock to the
//! phase it wants, and returns the messages player 1 (Ada, the host) would have been sent, in
//! order. `GameClient::load_fixture` feeds them through the same code a server's messages go
//! through, so everything downstream (Session, the roster, the chat, the clock) behaves as in
//! a real game.
//!
//! Times in the returned messages are moved so the current phase ends a fixed time after
//! `now`, and the clock shows a steady value in screenshots.

use webgame_game::{Game, Input, Outgoing, Seat, Timers};
use webgame_protocol::{
    ChatChannel, GameAction, GamePhase, LobbyCode, LobbyInfo, LobbyMember, NightStage, PlayerSlot,
    Role, ServerMessage, UserId,
};

/// The fixtures there are, for the gallery and for errors.
pub const NAMES: [&str; 8] = [
    "lobby_host_4",
    "lobby_full_15",
    "day_discussion",
    "day_voting",
    "day_trial",
    "night_choosing",
    "night_minigame",
    "spectating",
];

const PLAYERS: [&str; 15] = [
    "Ada", "Bram", "Cleo", "Dax", "Eve", "Finn", "Gus", "Hana", "Ivy", "Jon", "Kit", "Lea", "Moe",
    "Nia", "Otto",
];
/// Fifteen names, some long, for showing how the roster copes.
const LONG_PLAYERS: [&str; 15] = [
    "Ada",
    "Bartholomew Wainwright",
    "Cleo",
    "Dax",
    "Evangeline",
    "Finn",
    "Gus",
    "Hepzibah Goode",
    "Ivy",
    "Jon",
    "Kit",
    "Lea",
    "Mercy Lewis",
    "Nia",
    "Otto",
];
/// The roles a 6 player game deals, in seat order; player 1 (the one watching) is the Sheriff.
const ROLES_6: [Role; 6] = [
    Role::Sheriff,
    Role::Mafioso,
    Role::Doctor,
    Role::Jester,
    Role::Lookout,
    Role::Escort,
];
const CODE: &str = "WTCH92";
/// How long the current phase has left in a fixture, so the clock reads 0:42.
const LEFT_MS: u64 = 42_000;

/// The messages player 1 would have been sent to reach fixture `name`, timed against `now`.
pub fn build(name: &str, now: u64) -> Result<Vec<ServerMessage>, String> {
    match name {
        "lobby_host_4" => Ok(lobby(&PLAYERS[..4], false)),
        "lobby_full_15" => Ok(lobby(&LONG_PLAYERS, false)),
        "day_discussion" => game(now, 6, |phase| is_day(phase, 1, "discussion"), &[]),
        "day_voting" => game(
            now,
            6,
            |phase| is_day(phase, 1, "voting"),
            &[
                // Two players vote Cleo up; Bram whispers to Ada.
                Step::Vote(3, 2),
                Step::Vote(4, 2),
            ],
        ),
        "day_trial" => game(
            now,
            6,
            |phase| is_day(phase, 1, "judgement"),
            &[
                Step::Vote(1, 2),
                Step::Vote(3, 2),
                Step::Vote(4, 2),
                Step::Vote(5, 2),
            ],
        ),
        "night_choosing" => game(
            now,
            6,
            |phase| is_night(phase, 1, Some(NightStage::Choosing)),
            &[],
        ),
        "night_minigame" => game(
            now,
            6,
            |phase| is_night(phase, 1, Some(NightStage::Roleblock)),
            &[],
        ),
        "spectating" => spectating(now),
        _ => Err(format!(
            "No fixture called {name}. There are: {}",
            NAMES.join(", ")
        )),
    }
}

/// A scripted move, made as soon as the game allows it.
#[derive(Clone, Copy)]
enum Step {
    /// Seat `from` (from 0) votes seat `to` up for trial.
    Vote(u8, u8),
}

fn welcome() -> ServerMessage {
    ServerMessage::Welcome {
        user_id: UserId(1),
        username: PLAYERS[0].into(),
    }
}

fn members(names: &[&str]) -> Vec<LobbyMember> {
    names
        .iter()
        .enumerate()
        .map(|(i, name)| LobbyMember {
            user_id: UserId(i as u64 + 1),
            name: (*name).into(),
            slot: PlayerSlot(i as u8),
            connected: true,
            appearance: None,
        })
        .collect()
}

fn lobby_info(names: &[&str], in_game: bool) -> ServerMessage {
    ServerMessage::Lobby(LobbyInfo {
        code: LobbyCode::parse(CODE).expect("a valid code"),
        host: UserId(1),
        members: members(names),
        in_game,
    })
}

fn lobby(names: &[&str], in_game: bool) -> Vec<ServerMessage> {
    vec![welcome(), lobby_info(names, in_game)]
}

fn seats(names: &[&str]) -> Vec<Seat> {
    names
        .iter()
        .enumerate()
        .map(|(i, name)| Seat {
            slot: PlayerSlot(i as u8),
            user_id: UserId(i as u64 + 1),
            name: (*name).into(),
        })
        .collect()
}

/// Plays a 6 player game from the start until `reached` says the phase is the one wanted,
/// making `steps` when they become possible, and returns player 1's messages.
fn game(
    now: u64,
    players: usize,
    reached: impl Fn(&GamePhase) -> bool,
    steps: &[Step],
) -> Result<Vec<ServerMessage>, String> {
    let names = &PLAYERS[..players];
    let (mut game, out) = Game::with_roles(seats(names), &ROLES_6[..players], 7, Timers::NORMAL, 0)
        .map_err(|err| err.message)?;
    let me = PlayerSlot(0);
    let mut messages = lobby(names, true);
    let mut clock = 0;
    keep(&mut messages, out, me);
    let mut done = vec![false; steps.len()];
    for _ in 0..200 {
        for (i, step) in steps.iter().enumerate() {
            if done[i] {
                continue;
            }
            let Step::Vote(from, to) = *step;
            let input = Input::Action(GameAction::Vote(Some(PlayerSlot(to))));
            if let Ok(out) = game.handle(PlayerSlot(from), input, clock) {
                keep(&mut messages, out, me);
                done[i] = true;
            }
        }
        if reached(game.phase()) {
            // Some chat in the log, as players would have.
            if game.phase().is_day() {
                for (from, text) in [(1, "I was home all night."), (2, "Cleo, where were you?")] {
                    let input = Input::Chat {
                        channel: ChatChannel::General,
                        text: text.into(),
                    };
                    if let Ok(out) = game.handle(PlayerSlot(from), input, clock) {
                        keep(&mut messages, out, me);
                    }
                }
            }
            let shift = (now + LEFT_MS).wrapping_sub(game.deadline().unwrap_or(clock + LEFT_MS));
            return Ok(retime(messages, shift));
        }
        clock = game.wake_at().unwrap_or(clock + 1_000).max(clock + 1);
        keep(&mut messages, game.tick(clock), me);
    }
    Err("The game never reached that phase".into())
}

/// A game in progress that player 7 joins late, as a spectator.
fn spectating(now: u64) -> Result<Vec<ServerMessage>, String> {
    let names = &PLAYERS[..7];
    let (mut game, _) = Game::with_roles(seats(&names[..6]), &ROLES_6, 7, Timers::NORMAL, 0)
        .map_err(|err| err.message)?;
    let me = PlayerSlot(6);
    let mut clock = 0;
    while !is_day(game.phase(), 1, "discussion") {
        clock = game.wake_at().unwrap_or(clock + 1_000).max(clock + 1);
        game.tick(clock);
        if clock > 10_000_000 {
            return Err("The game never reached day 1".into());
        }
    }
    game.add_spectator(me, UserId(7), names[6].into());
    let mut messages = vec![
        ServerMessage::Welcome {
            user_id: UserId(7),
            username: names[6].into(),
        },
        lobby_info(names, true),
    ];
    messages.extend(game.snapshot(me));
    let shift = (now + LEFT_MS).wrapping_sub(game.deadline().unwrap_or(clock + LEFT_MS));
    Ok(retime(messages, shift))
}

fn keep(messages: &mut Vec<ServerMessage>, out: Vec<Outgoing>, me: PlayerSlot) {
    messages.extend(
        out.into_iter()
            .filter(|o| o.to.includes(me))
            .map(|o| o.message),
    );
}

/// Moves every deadline by `shift` milliseconds, from the game's clock to the real one.
fn retime(messages: Vec<ServerMessage>, shift: u64) -> Vec<ServerMessage> {
    messages
        .into_iter()
        .map(|message| match message {
            ServerMessage::Phase { phase, ends_at_ms } => ServerMessage::Phase {
                phase,
                ends_at_ms: ends_at_ms.wrapping_add(shift),
            },
            ServerMessage::Minigame { game, ends_at_ms } => ServerMessage::Minigame {
                game,
                ends_at_ms: ends_at_ms.wrapping_add(shift),
            },
            other => other,
        })
        .collect()
}

fn is_day(phase: &GamePhase, day: u32, stage: &str) -> bool {
    match phase {
        GamePhase::Day { day: d, stage: s } if *d == day => {
            format!("{s:?}").to_lowercase().starts_with(stage)
        }
        _ => false,
    }
}

fn is_night(phase: &GamePhase, night: u32, stage: Option<NightStage>) -> bool {
    match phase {
        GamePhase::Night { night: n, stage: s } if *n == night => stage.is_none_or(|w| w == *s),
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_fixture_builds() {
        for name in NAMES {
            let messages = build(name, 1_000_000).unwrap_or_else(|err| panic!("{name}: {err}"));
            assert!(messages.len() >= 2, "{name} has messages");
        }
    }

    #[test]
    fn a_game_fixture_reaches_its_phase() {
        let messages = build("day_voting", 1_000_000).unwrap();
        let last_phase = messages.iter().rev().find_map(|m| match m {
            ServerMessage::Phase { phase, ends_at_ms } => Some((phase.clone(), *ends_at_ms)),
            _ => None,
        });
        let (phase, ends_at) = last_phase.expect("a phase");
        assert!(is_day(&phase, 1, "voting"), "{phase:?}");
        assert_eq!(ends_at, 1_000_000 + LEFT_MS);
    }

    #[test]
    fn unknown_fixtures_say_which_exist() {
        let err = build("nope", 0).unwrap_err();
        assert!(err.contains("lobby_host_4"));
    }
}
