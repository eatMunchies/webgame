use std::net::IpAddr;
use std::path::PathBuf;

use clap::Parser;
use webgame_game::Timers;
use webgame_server::{Config, app, db::Db};

/// Runs the game server.
#[derive(Parser)]
struct Args {
    /// Address to listen on. Use 0.0.0.0 to accept other machines on your network.
    #[arg(long, default_value = "127.0.0.1")]
    host: IpAddr,
    #[arg(long, default_value_t = 9090)]
    port: u16,
    /// SQLite file for users, lobbies, and game logs. Created if missing.
    #[arg(long, default_value = "webgame.db")]
    db: PathBuf,
    /// Short phases (15s discussion, under a minute of night) for trying the game out. Also
    /// lets players have the server roll their minigames at random, which the terminal client
    /// does since it can't show them.
    #[arg(long)]
    fast: bool,
    /// Seed every game the same way, to replay one.
    #[arg(long)]
    seed: Option<u64>,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse();
    let db = Db::open(&args.db)?;
    let config = Config {
        timers: if args.fast {
            Timers::FAST
        } else {
            Timers::NORMAL
        },
        seed: args.seed,
        rolls: args.fast,
    };
    let listener = tokio::net::TcpListener::bind((args.host, args.port)).await?;
    println!(
        "webgame server on ws://{}/ws (database {})",
        listener.local_addr()?,
        args.db.display()
    );
    axum::serve(listener, app(db, config)).await?;
    Ok(())
}
