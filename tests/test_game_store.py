import pytest

from src.game_store import Game, GameStore, ShoppingCart, build_demo_store


def test_store_lists_games_sorted_by_title():
    store = build_demo_store()
    titles = [game.title for game in store.list_games()]
    assert titles == sorted(titles, key=str.lower)


def test_add_to_cart_and_checkout_updates_stock():
    store = GameStore()
    store.add_game(Game(game_id="g1", title="Nova Quest", genre="RPG", price=50.0, stock=5))

    cart = ShoppingCart()
    store.add_to_cart(cart, "g1", quantity=2)

    total = store.checkout(cart)

    assert total == 100.0
    assert store.get_game("g1").stock == 3
    assert cart.items == {}


def test_add_to_cart_rejects_quantity_exceeding_stock():
    store = GameStore()
    store.add_game(Game(game_id="g1", title="Nova Quest", genre="RPG", price=50.0, stock=1))

    cart = ShoppingCart()
    with pytest.raises(ValueError, match="not enough stock"):
        store.add_to_cart(cart, "g1", quantity=2)


def test_checkout_rejects_empty_cart():
    store = build_demo_store()
    cart = ShoppingCart()

    with pytest.raises(ValueError, match="cart is empty"):
        store.checkout(cart)
