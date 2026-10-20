use serde::{Deserialize, Serialize};

use crate::{DayStage, Faction, GamePhase, PlayerSlot, Role};

/// Where a chat message goes. Who may write to and read each channel depends on the phase and
/// the player, and is decided by [`ChatContext`].
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum ChatChannel {
    /// Everyone in the lobby, before a game starts.
    Lobby,
    /// The town square: living players by day. Everyone reads it, the dead included.
    General,
    /// A private message during the day. Everyone sees that it was sent, only the two players
    /// see what it says.
    Whisper { to: PlayerSlot },
    /// The Jailer and their prisoner, at night. The prisoner doesn't learn who the Jailer is.
    Jail,
    /// The Mafia, at night.
    Mafia,
    /// The dead, at any time. A living Medium can read and write it at night, anonymously.
    Dead,
}

/// Who a chat message is shown as coming from.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum ChatSender {
    Player(PlayerSlot),
    /// The Jailer, unnamed, in jail chat.
    Jailer,
    /// A living Medium, unnamed, in dead chat.
    Medium,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatMessage {
    pub channel: ChatChannel,
    pub from: ChatSender,
    pub text: String,
}

/// A player's part in tonight's jailing.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum JailStatus {
    Free,
    Jailer { prisoner: PlayerSlot },
    Prisoner,
}

/// Everything about one player that decides which chat channels they can use. The server
/// builds one to check each message; the client builds its own to pick a default channel and
/// show only the channels that will work.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ChatContext {
    pub phase: GamePhase,
    pub slot: PlayerSlot,
    pub alive: bool,
    pub role: Role,
    pub jail: JailStatus,
}

impl ChatContext {
    /// Whether this player may write to a channel right now. For a whisper the server also
    /// checks that the other player is alive.
    pub fn can_send(&self, channel: ChatChannel) -> bool {
        let night = self.phase.is_night();
        match channel {
            ChatChannel::Lobby => false,
            ChatChannel::General => match &self.phase {
                GamePhase::GameOver => true,
                GamePhase::Day { stage, .. } => {
                    self.alive
                        && match stage {
                            // Only the accused speaks while defending and in their last words.
                            DayStage::Defense { accused } | DayStage::LastWords { accused } => {
                                *accused == self.slot
                            }
                            _ => true,
                        }
                }
                _ => false,
            },
            ChatChannel::Whisper { to } => self.phase.is_day() && self.alive && to != self.slot,
            ChatChannel::Jail => night && self.alive && self.jail != JailStatus::Free,
            ChatChannel::Mafia => night && self.alive && self.role.faction() == Faction::Mafia,
            ChatChannel::Dead => !self.alive || (night && self.role == Role::Medium),
        }
    }

    /// Whether this player sees messages on a shared channel. Whispers are only ever seen by
    /// the two players in them, so this says no for them.
    pub fn can_read(&self, channel: ChatChannel) -> bool {
        let night = self.phase.is_night();
        match channel {
            ChatChannel::Lobby | ChatChannel::Whisper { .. } => false,
            ChatChannel::General => true,
            ChatChannel::Jail => night && self.alive && self.jail != JailStatus::Free,
            ChatChannel::Mafia => self.alive && self.role.faction() == Faction::Mafia,
            ChatChannel::Dead => !self.alive || (night && self.role == Role::Medium),
        }
    }

    /// The channel a plain message goes to: the town square by day; by night the jail, the
    /// Mafia, or the dead, whichever this player has.
    pub fn default_channel(&self) -> Option<ChatChannel> {
        [
            ChatChannel::General,
            ChatChannel::Jail,
            ChatChannel::Mafia,
            ChatChannel::Dead,
        ]
        .into_iter()
        .find(|channel| self.can_send(*channel))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn context(phase: GamePhase, alive: bool, role: Role) -> ChatContext {
        ChatContext {
            phase,
            slot: PlayerSlot(0),
            alive,
            role,
            jail: JailStatus::Free,
        }
    }

    fn day(stage: DayStage) -> GamePhase {
        GamePhase::Day { day: 1, stage }
    }

    const NIGHT: GamePhase = GamePhase::Night { night: 1 };

    #[test]
    fn town_square_is_for_the_living_by_day() {
        let discussion = day(DayStage::Discussion);
        assert!(context(discussion.clone(), true, Role::Doctor).can_send(ChatChannel::General));
        assert!(!context(discussion.clone(), false, Role::Doctor).can_send(ChatChannel::General));
        assert!(context(discussion, false, Role::Doctor).can_read(ChatChannel::General));
        assert!(!context(NIGHT, true, Role::Doctor).can_send(ChatChannel::General));
    }

    #[test]
    fn only_the_accused_speaks_in_their_defense() {
        let me = context(
            day(DayStage::Defense {
                accused: PlayerSlot(0),
            }),
            true,
            Role::Doctor,
        );
        let other = context(
            day(DayStage::Defense {
                accused: PlayerSlot(3),
            }),
            true,
            Role::Doctor,
        );
        assert!(me.can_send(ChatChannel::General));
        assert!(!other.can_send(ChatChannel::General));
        assert!(other.can_send(ChatChannel::Whisper { to: PlayerSlot(3) }));
    }

    #[test]
    fn night_channels() {
        let mafioso = context(NIGHT, true, Role::Mafioso);
        assert_eq!(mafioso.default_channel(), Some(ChatChannel::Mafia));
        assert!(!context(NIGHT, true, Role::Doctor).can_read(ChatChannel::Mafia));
        assert_eq!(context(NIGHT, true, Role::Doctor).default_channel(), None);

        let medium = context(NIGHT, true, Role::Medium);
        assert!(medium.can_send(ChatChannel::Dead) && medium.can_read(ChatChannel::Dead));
        let medium_by_day = context(day(DayStage::Discussion), true, Role::Medium);
        assert!(!medium_by_day.can_read(ChatChannel::Dead));

        let mut prisoner = context(NIGHT, true, Role::Mafioso);
        prisoner.jail = JailStatus::Prisoner;
        assert_eq!(prisoner.default_channel(), Some(ChatChannel::Jail));
    }

    #[test]
    fn dead_talk_to_the_dead() {
        let ghost = context(day(DayStage::Discussion), false, Role::Mafioso);
        assert_eq!(ghost.default_channel(), Some(ChatChannel::Dead));
        assert!(!ghost.can_read(ChatChannel::Mafia));
        assert!(!ghost.can_send(ChatChannel::Whisper { to: PlayerSlot(2) }));
    }
}
