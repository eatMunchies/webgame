class_name BlackjackGame
extends RefCounted

## Blackjack against the dealer, from a shoe of real decks (two by default),
## so the odds shift with the cards already dealt, as at a casino table.
##
## A hand: the player and dealer get two cards each, the dealer's second face
## down. The player hits (takes a card) or stands. Going over 21 busts and
## loses. Standing turns the dealer's card over, and the dealer draws to 17
## or more, standing on soft 17. Closer to 21 wins; a tie pushes. Two cards
## making 21 is a blackjack, and either side holding one ends the hand at
## once. There is no splitting or doubling, to keep a hand short.
##
## bust_chance() is the odds that hitting busts the player, counted from
## every card the player hasn't seen (the shoe and the dealer's face down
## card), which is what the 2-deck shoe is for.
##
## A card is a number from 0 to 51: rank is card % 13 (0 an ace, then 2 to
## 10, then jack, queen, king), suit is card / 13.

const RANKS := ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
## The shoe is reshuffled before a hand when fewer cards than this are left.
const RESHUFFLE_AT := 20
## How long the dealer takes over each card it draws, in seconds.
const DEALER_SECONDS := 0.45

var decks := 2
## The cards left to deal, dealt from the back.
var shoe: Array[int] = []
var player: Array[int] = []
var dealer: Array[int] = []
## Whether the dealer's second card is still face down.
var hole_hidden := true
## "player" while the player decides, "dealer" while it draws, "over" once
## decided.
var turn := "over"
## Once over: "blackjack", "win", "push", "lose" or "bust".
var outcome := ""

var _rng := RandomNumberGenerator.new()
var _dealer_wait := 0.0


## A seed of -1 picks a random one.
func _init(seed_value := -1, deck_count := 2) -> void:
	if seed_value < 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	decks = deck_count
	shuffle()


## Fills the shoe with every card of every deck, shuffled.
func shuffle() -> void:
	shoe = []
	for deck in decks:
		for card in 52:
			shoe.append(card)
	# Fisher-Yates with our own RNG, so a seed always deals the same.
	for i in range(shoe.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var swap := shoe[i]
		shoe[i] = shoe[j]
		shoe[j] = swap


## Deals a new hand. A blackjack on either side ends it straight away.
func deal() -> void:
	if shoe.size() < RESHUFFLE_AT:
		shuffle()
	player = [shoe.pop_back(), shoe.pop_back()]
	dealer = [shoe.pop_back(), shoe.pop_back()]
	hole_hidden = true
	outcome = ""
	turn = "player"
	if total(player) == 21 or total(dealer) == 21:
		_finish()


## Takes a card. Busting ends the hand, and reaching 21 stands.
func hit() -> void:
	if turn != "player":
		return
	player.append(shoe.pop_back())
	if total(player) > 21:
		_finish()
	elif total(player) == 21:
		stand()


## Stops taking cards; the dealer plays out its hand over the next moments.
func stand() -> void:
	if turn != "player":
		return
	turn = "dealer"
	hole_hidden = false
	_dealer_wait = DEALER_SECONDS


## Moves time on, drawing the dealer's cards one at a time.
func advance(delta: float) -> void:
	if turn != "dealer":
		return
	_dealer_wait -= delta
	if _dealer_wait > 0.0:
		return
	if total(dealer) < 17:
		dealer.append(shoe.pop_back())
		_dealer_wait = DEALER_SECONDS
	else:
		_finish()


## The odds, from 0 to 1, that the next card busts the player, out of the
## cards they can't see: what's left in the shoe and the dealer's face down
## card while it's hidden.
func bust_chance() -> float:
	var unseen := shoe.duplicate()
	if hole_hidden and dealer.size() > 1:
		unseen.append(dealer[1])
	if unseen.is_empty():
		return 0.0
	var busts := 0
	for card in unseen:
		if total(player + [card]) > 21:
			busts += 1
	return float(busts) / unseen.size()


## A hand's best total: aces count 11 unless that would bust.
static func total(hand: Array) -> int:
	var sum := 0
	var aces := 0
	for card: int in hand:
		var rank := card % 13
		if rank == 0:
			aces += 1
			sum += 1
		else:
			sum += mini(rank + 1, 10)
	if aces > 0 and sum + 10 <= 21:
		sum += 10
	return sum


## What the player can see of the dealer's total: the face up card alone
## while the other is hidden.
func dealer_shown_total() -> int:
	return total([dealer[0]]) if hole_hidden else total(dealer)


static func rank_name(card: int) -> String:
	return RANKS[card % 13]


## Whether a card is a heart or diamond.
static func is_red(card: int) -> bool:
	return card / 13 % 4 in [1, 2]


func _finish() -> void:
	turn = "over"
	hole_hidden = false
	var mine := total(player)
	var theirs := total(dealer)
	var my_blackjack := mine == 21 and player.size() == 2
	var their_blackjack := theirs == 21 and dealer.size() == 2
	if mine > 21:
		outcome = "bust"
	elif my_blackjack and their_blackjack:
		outcome = "push"
	elif my_blackjack:
		outcome = "blackjack"
	elif their_blackjack:
		outcome = "lose"
	elif theirs > 21 or mine > theirs:
		outcome = "win"
	elif mine == theirs:
		outcome = "push"
	else:
		outcome = "lose"
