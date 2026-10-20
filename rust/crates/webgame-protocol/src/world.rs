//! The town everyone walks around in: where each player's character is and what it looks like.
//! None of this affects the game's rules; it is relayed so every client draws the same town.

use serde::{Deserialize, Serialize};

/// Positions are whole pixels from 0 to this, which is larger than any town.
pub const MAX_COORD: i32 = 4096;
/// An appearance has at most this many equipped items.
pub const MAX_APPEARANCE_ITEMS: usize = 16;
/// Style and item names (art folder names) are at most this many bytes.
pub const MAX_STYLE_LEN: usize = 32;

/// Which way a character faces. The order matches the rows of the character sprite sheets and
/// the client's `Character.Facing` enum.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum Facing {
    #[default]
    Down,
    Left,
    Right,
    Up,
}

impl Facing {
    /// The sprite row number, the same as the Godot enum's value.
    pub fn index(self) -> u8 {
        self as u8
    }

    pub fn from_index(index: u8) -> Option<Facing> {
        [Facing::Down, Facing::Left, Facing::Right, Facing::Up]
            .get(usize::from(index))
            .copied()
    }
}

/// Where a player's character stands and whether it is walking, so other clients can draw it.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Movement {
    pub x: i32,
    pub y: i32,
    pub facing: Facing,
    pub walking: bool,
}

impl Movement {
    /// Whether the position is inside the area any town could use.
    pub fn is_valid(&self) -> bool {
        (0..=MAX_COORD).contains(&self.x) && (0..=MAX_COORD).contains(&self.y)
    }
}

/// How a player's character looks, as chosen in the customizer. The names are art folder names
/// that the client looks up; the server only checks their size.
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Appearance {
    pub body_type: String,
    pub gender: String,
    /// The skin color as 0xRRGGBBAA.
    pub skin_color: u32,
    /// (slot, item) pairs, like ("hat", "cowboy").
    pub items: Vec<(String, String)>,
}

impl Appearance {
    /// Checks the sizes the server accepts.
    pub fn validate(&self) -> Result<(), &'static str> {
        let names = [&self.body_type, &self.gender]
            .into_iter()
            .chain(self.items.iter().flat_map(|(slot, item)| [slot, item]));
        if self.items.len() > MAX_APPEARANCE_ITEMS {
            Err("Too many items.")
        } else if names.into_iter().any(|name| name.len() > MAX_STYLE_LEN) {
            Err("A style name is too long.")
        } else {
            Ok(())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn facing_matches_the_sprite_rows() {
        for index in 0..4 {
            assert_eq!(Facing::from_index(index).unwrap().index(), index);
        }
        assert_eq!(Facing::from_index(4), None);
    }

    #[test]
    fn movement_stays_in_bounds() {
        let at = |x, y| Movement {
            x,
            y,
            facing: Facing::Down,
            walking: false,
        };
        assert!(at(0, MAX_COORD).is_valid());
        assert!(!at(-1, 0).is_valid());
        assert!(!at(0, MAX_COORD + 1).is_valid());
    }

    #[test]
    fn oversized_appearances_are_refused() {
        let mut look = Appearance {
            body_type: "regular".into(),
            gender: "male".into(),
            skin_color: 0xf5cbb0ff,
            items: vec![("hat".into(), "cowboy".into())],
        };
        assert!(look.validate().is_ok());
        look.items[0].1 = "x".repeat(MAX_STYLE_LEN + 1);
        assert!(look.validate().is_err());
        look.items = vec![("a".into(), "b".into()); MAX_APPEARANCE_ITEMS + 1];
        assert!(look.validate().is_err());
    }
}
