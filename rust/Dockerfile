# The game server as a container image. Build from the rust/ directory:
#   docker build -t webgame-server rust/
# The image listens on 0.0.0.0:9090 and keeps its SQLite file in /data, so mount a volume there.

# Stage 1: compile the server. The Rust image has the C compiler rusqlite needs for its bundled
# SQLite.
FROM rust:1-slim-bookworm AS build
WORKDIR /src
COPY . .
RUN cargo build --release --locked -p webgame-server

# Stage 2: a small runtime image with just the binary, run as an unprivileged user.
FROM debian:bookworm-slim
RUN useradd --system --uid 10001 --no-create-home webgame \
    && mkdir /data \
    && chown webgame /data
COPY --from=build /src/target/release/webgame-server /usr/local/bin/webgame-server
USER webgame
EXPOSE 9090
ENTRYPOINT ["webgame-server", "--host", "0.0.0.0", "--db", "/data/webgame.db"]
