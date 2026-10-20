use std::fmt;

use serde::{Deserialize, Serialize};

use crate::{CODE_ALPHABET, CODE_LENGTH, MAX_NAME_LEN};

/// A user, stable across connections. There are no accounts yet, so it is a hash of the
/// username: the same name always gets the same id, which is what lets a player reconnect to
/// their seat.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub struct UserId(pub u64);

impl UserId {
    /// The id for a username. Case is ignored, so "Ada" and "ada" are the same user.
    pub fn from_username(username: &str) -> Self {
        // 64-bit FNV-1a. It is stable across builds and platforms, unlike std's hasher, so the
        // client and server (and the database) always agree on it.
        let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
        for byte in username.trim().to_lowercase().bytes() {
            hash ^= u64::from(byte);
            hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
        }
        // SQLite stores signed 64-bit integers, so keep the id positive.
        UserId(hash >> 1)
    }
}

/// A seat in a lobby and in its game, which is also the lot the player's house is on. Seats
/// count from 0 on the wire; people see them counted from 1, which is what `Display` prints.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub struct PlayerSlot(pub u8);

impl PlayerSlot {
    /// The seat a person means when they type a number counted from 1, if it is in range.
    pub fn from_number(number: usize) -> Option<Self> {
        (1..=crate::MAX_PLAYERS)
            .contains(&number)
            .then(|| PlayerSlot((number - 1) as u8))
    }
}

impl fmt::Display for PlayerSlot {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0 + 1)
    }
}

/// A lobby's join code: [`CODE_LENGTH`] characters from [`CODE_ALPHABET`]. A value of this type
/// is always well formed, including one decoded from the network.
#[derive(Clone, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(try_from = "String", into = "String")]
pub struct LobbyCode(String);

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CodeError {
    WrongLength,
    BadCharacter(char),
}

impl fmt::Display for CodeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            CodeError::WrongLength => write!(f, "lobby codes are {CODE_LENGTH} characters"),
            CodeError::BadCharacter(c) => write!(f, "\"{c}\" can't be in a lobby code"),
        }
    }
}

impl std::error::Error for CodeError {}

impl LobbyCode {
    /// Reads a code the way a person might type it: any case, with spaces or dashes.
    pub fn parse(raw: &str) -> Result<Self, CodeError> {
        let clean: String = raw
            .chars()
            .filter(|c| *c != ' ' && *c != '-')
            .map(|c| c.to_ascii_uppercase())
            .collect();
        if let Some(bad) = clean.chars().find(|c| !CODE_ALPHABET.contains(*c)) {
            return Err(CodeError::BadCharacter(bad));
        }
        if clean.chars().count() != CODE_LENGTH {
            return Err(CodeError::WrongLength);
        }
        Ok(LobbyCode(clean))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl TryFrom<String> for LobbyCode {
    type Error = CodeError;

    fn try_from(value: String) -> Result<Self, Self::Error> {
        LobbyCode::parse(&value)
    }
}

impl From<LobbyCode> for String {
    fn from(code: LobbyCode) -> Self {
        code.0
    }
}

impl fmt::Display for LobbyCode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum NameError {
    Empty,
    TooLong,
    BadCharacter(char),
}

impl fmt::Display for NameError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            NameError::Empty => write!(f, "names can't be empty"),
            NameError::TooLong => write!(f, "names are at most {MAX_NAME_LEN} characters"),
            NameError::BadCharacter(c) => write!(f, "\"{c}\" can't be in a name"),
        }
    }
}

impl std::error::Error for NameError {}

/// Checks a username and returns it trimmed. Names are letters, digits, spaces, `_` and `-`.
pub fn validate_username(raw: &str) -> Result<String, NameError> {
    let name = raw.trim();
    if name.is_empty() {
        return Err(NameError::Empty);
    }
    if name.chars().count() > MAX_NAME_LEN {
        return Err(NameError::TooLong);
    }
    if let Some(bad) = name
        .chars()
        .find(|c| !(c.is_alphanumeric() || matches!(c, ' ' | '_' | '-')))
    {
        return Err(NameError::BadCharacter(bad));
    }
    Ok(name.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn user_id_ignores_case_and_spaces() {
        assert_eq!(
            UserId::from_username("Ada"),
            UserId::from_username("  ada ")
        );
        assert_ne!(UserId::from_username("Ada"), UserId::from_username("Bram"));
        assert!(UserId::from_username("Ada").0 <= i64::MAX as u64);
    }

    #[test]
    fn lobby_codes_are_normalized_and_checked() {
        assert_eq!(LobbyCode::parse("abc-def").unwrap().as_str(), "ABCDEF");
        assert_eq!(LobbyCode::parse("ABC"), Err(CodeError::WrongLength));
        assert_eq!(
            LobbyCode::parse("ABCDE0"),
            Err(CodeError::BadCharacter('0'))
        );
    }

    #[test]
    fn slots_are_shown_from_one() {
        assert_eq!(PlayerSlot(0).to_string(), "1");
        assert_eq!(PlayerSlot::from_number(15), Some(PlayerSlot(14)));
        assert_eq!(PlayerSlot::from_number(0), None);
        assert_eq!(PlayerSlot::from_number(16), None);
    }

    #[test]
    fn usernames_are_validated() {
        assert_eq!(validate_username("  Ada "), Ok("Ada".to_string()));
        assert_eq!(validate_username(" "), Err(NameError::Empty));
        assert_eq!(validate_username("a!"), Err(NameError::BadCharacter('!')));
        assert_eq!(validate_username(&"x".repeat(17)), Err(NameError::TooLong));
    }
}
