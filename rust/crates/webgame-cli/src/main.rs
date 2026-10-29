//! A terminal client for trying the game without Godot. It speaks the same protocol as the
//! game will: `webgame-protocol` messages, postcard-encoded, over a WebSocket.
//!
//! Run one per player, each in its own terminal:
//!
//! ```text
//! cargo run -p webgame-cli -- --name Ada --create
//! cargo run -p webgame-cli -- --name Bram --join ABC234
//! ```
//!
//! It can't show the night's minigames, so it asks the server to roll each skill check and
//! fight it is given. Servers started with `--fast` allow that; others refuse, and the
//! minigame fails.

use std::time::{SystemTime, UNIX_EPOCH};

use clap::Parser;
use futures_util::{SinkExt, StreamExt};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio_tungstenite::connect_async;
use tokio_tungstenite::tungstenite::Message;
use webgame_protocol::{
    ClientMessage, GameAction, LobbyCode, Minigame, MinigamePlay, PROTOCOL_VERSION, ServerMessage,
    decode, encode,
};

use webgame_client::{Command, HELP, State};

#[derive(Parser)]
#[command(about = "Play webgame from a terminal")]
struct Args {
    /// Your username. The same name always gets the same user id, so reconnecting with it
    /// puts you back in your seat.
    #[arg(long)]
    name: String,
    /// The server's WebSocket address.
    #[arg(long, default_value = "ws://127.0.0.1:9090/ws")]
    server: String,
    /// Open a new lobby once connected.
    #[arg(long, conflicts_with = "join")]
    create: bool,
    /// Join the lobby with this code once connected.
    #[arg(long, value_parser = LobbyCode::parse)]
    join: Option<LobbyCode>,
}

#[tokio::main]
async fn main() {
    let args = Args::parse();
    if let Err(err) = run(args).await {
        eprintln!("{err}");
        std::process::exit(1);
    }
}

async fn run(args: Args) -> Result<(), String> {
    let (socket, _) = connect_async(&args.server).await.map_err(|err| {
        format!(
            "Couldn't reach {}: {err}. Is the server running?",
            args.server
        )
    })?;
    let (mut sink, mut stream) = socket.split();
    let mut send = async |message: ClientMessage| {
        sink.send(Message::Binary(encode(&message).into()))
            .await
            .map_err(|err| format!("Lost the server: {err}"))
    };

    send(ClientMessage::Hello {
        version: PROTOCOL_VERSION,
        username: args.name.clone(),
    })
    .await?;
    if args.create {
        send(ClientMessage::CreateLobby).await?;
    } else if let Some(code) = args.join {
        send(ClientMessage::JoinLobby { code }).await?;
    }

    let mut state = State::default();
    let mut lines = BufReader::new(tokio::io::stdin()).lines();
    loop {
        tokio::select! {
            frame = stream.next() => {
                let message = match frame {
                    Some(Ok(Message::Binary(bytes))) => decode::<ServerMessage>(&bytes)
                        .map_err(|err| format!("The server sent something unreadable: {err}"))?,
                    Some(Ok(Message::Close(_))) | None => {
                        return Err("The server closed the connection.".into());
                    }
                    Some(Ok(_)) => continue,
                    Some(Err(err)) => return Err(format!("Lost the server: {err}")),
                };
                let roll = matches!(
                    message,
                    ServerMessage::Minigame { game, .. } if game != Minigame::Passive
                );
                let lines = state.apply(message);
                print(&state, lines);
                if roll {
                    send(ClientMessage::Game(GameAction::Minigame(MinigamePlay::Roll))).await?;
                }
            }
            line = lines.next_line() => {
                let Some(line) = line.map_err(|err| err.to_string())? else {
                    return Ok(());
                };
                match webgame_client::parse(&line, &state) {
                    Ok(Command::Send(message)) => {
                        if let ClientMessage::Game(GameAction::SetLastWill(will)) = &message {
                            state.will = will.clone();
                        }
                        send(message).await?;
                    }
                    Ok(Command::Players) => println!("{}", state.players_text()),
                    Ok(Command::Role) => println!("{}", state.role_text()),
                    Ok(Command::Roles) => println!("{}", state.roles_text()),
                    Ok(Command::CopyFrom(slot)) => println!("{}", state.copy_from(slot)),
                    Ok(Command::Help) => println!("{HELP}"),
                    Ok(Command::Quit) => return Ok(()),
                    Err(err) if err.is_empty() => {}
                    Err(err) => println!("! {err}"),
                }
            }
        }
    }
}

/// Prints lines under the current phase and the time left in it, like
/// `[Day 1 Voting, 3 trials left 0:42] Ada (1): hi`.
fn print(state: &State, lines: Vec<String>) {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
    for line in lines {
        println!("[{}] {line}", state.clock(now));
    }
}
