from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List


@dataclass(frozen=True)
class Game:
    """Represents a game available in the store."""

    game_id: str
    title: str
    genre: str
    price: float
    stock: int = 0


@dataclass
class CartItem:
    game: Game
    quantity: int

    @property
    def subtotal(self) -> float:
        return round(self.game.price * self.quantity, 2)


@dataclass
class ShoppingCart:
    items: Dict[str, CartItem] = field(default_factory=dict)

    def add(self, game: Game, quantity: int = 1) -> None:
        if quantity <= 0:
            raise ValueError("quantity must be positive")
        if game.game_id in self.items:
            existing = self.items[game.game_id]
            self.items[game.game_id] = CartItem(game=game, quantity=existing.quantity + quantity)
        else:
            self.items[game.game_id] = CartItem(game=game, quantity=quantity)

    def clear(self) -> None:
        self.items.clear()

    @property
    def total(self) -> float:
        return round(sum(item.subtotal for item in self.items.values()), 2)


class GameStore:
    """In-memory game store with inventory and checkout flow."""

    def __init__(self) -> None:
        self._inventory: Dict[str, Game] = {}

    def add_game(self, game: Game) -> None:
        if game.price < 0:
            raise ValueError("price cannot be negative")
        if game.stock < 0:
            raise ValueError("stock cannot be negative")
        if game.game_id in self._inventory:
            raise ValueError(f"game_id '{game.game_id}' already exists")
        self._inventory[game.game_id] = game

    def list_games(self) -> List[Game]:
        return sorted(self._inventory.values(), key=lambda g: g.title.lower())

    def get_game(self, game_id: str) -> Game:
        try:
            return self._inventory[game_id]
        except KeyError as exc:
            raise KeyError(f"unknown game_id '{game_id}'") from exc

    def add_to_cart(self, cart: ShoppingCart, game_id: str, quantity: int = 1) -> None:
        game = self.get_game(game_id)
        if quantity > game.stock:
            raise ValueError(f"not enough stock for '{game.title}'")

        already_in_cart = cart.items.get(game_id, CartItem(game=game, quantity=0)).quantity
        if already_in_cart + quantity > game.stock:
            raise ValueError(f"cart quantity exceeds stock for '{game.title}'")

        cart.add(game=game, quantity=quantity)

    def checkout(self, cart: ShoppingCart) -> float:
        if not cart.items:
            raise ValueError("cart is empty")

        # Validate stock before applying mutation.
        for item in cart.items.values():
            current = self.get_game(item.game.game_id)
            if item.quantity > current.stock:
                raise ValueError(f"not enough stock for '{current.title}'")

        # Deduct stock.
        for item in cart.items.values():
            current = self.get_game(item.game.game_id)
            self._inventory[current.game_id] = Game(
                game_id=current.game_id,
                title=current.title,
                genre=current.genre,
                price=current.price,
                stock=current.stock - item.quantity,
            )

        total = cart.total
        cart.clear()
        return total


def build_demo_store() -> GameStore:
    store = GameStore()
    store.add_game(Game(game_id="g001", title="Elder Realms VI", genre="RPG", price=59.99, stock=10))
    store.add_game(Game(game_id="g002", title="Turbo Drift", genre="Racing", price=39.99, stock=8))
    store.add_game(Game(game_id="g003", title="Sky Colony", genre="Strategy", price=29.99, stock=15))
    return store
