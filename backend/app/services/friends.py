import uuid


def friendship_pair(user_a: uuid.UUID, user_b: uuid.UUID) -> tuple[uuid.UUID, uuid.UUID]:
    if user_a == user_b:
        return user_a, user_b

    if user_a.int < user_b.int:
        return user_a, user_b

    return user_b, user_a