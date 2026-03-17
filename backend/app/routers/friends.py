from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Friendship, User
from app.schemas import FriendAddRequest, FriendRead
from app.security import get_current_user
from app.services.friends import friendship_pair
from app.services.users import parse_handle

router = APIRouter(prefix='/friends', tags=['friends'])


def _friend_read(friend_user: User, created_at) -> FriendRead:
    return FriendRead(
        user_id=friend_user.id,
        username=friend_user.username,
        tag=friend_user.tag,
        handle=friend_user.handle,
        display_name=friend_user.display_name,
        avatar_url=friend_user.avatar_url,
        created_at=created_at,
    )


@router.get('', response_model=list[FriendRead])
def list_friends(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)) -> list[FriendRead]:
    friendships = db.scalars(
        select(Friendship)
        .where(
            or_(
                Friendship.user_low_id == current_user.id,
                Friendship.user_high_id == current_user.id,
            )
        )
        .order_by(Friendship.created_at.desc())
    ).all()

    result: list[FriendRead] = []
    for friendship in friendships:
        peer_id = (
            friendship.user_high_id if friendship.user_low_id == current_user.id else friendship.user_low_id
        )
        peer = db.get(User, peer_id)
        if peer is None:
            continue
        if peer.is_platform_admin and not current_user.is_platform_admin:
            continue
        result.append(_friend_read(peer, friendship.created_at))

    return result


@router.post('/add', response_model=FriendRead, status_code=status.HTTP_201_CREATED)
def add_friend(
    payload: FriendAddRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> FriendRead:
    username_key, tag = parse_handle(payload.handle)
    target = db.scalar(select(User).where(User.username_key == username_key, User.tag == tag))

    if target is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='User not found.')
    if target.is_platform_admin and not current_user.is_platform_admin:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='User not found.')

    if target.id == current_user.id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='You cannot add yourself.')

    low, high = friendship_pair(current_user.id, target.id)
    existing = db.scalar(
        select(Friendship).where(Friendship.user_low_id == low, Friendship.user_high_id == high)
    )
    if existing is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='Already friends.')

    friendship = Friendship(user_low_id=low, user_high_id=high)
    db.add(friendship)
    db.commit()
    db.refresh(friendship)

    return _friend_read(target, friendship.created_at)


@router.delete('/{friend_user_id}', status_code=status.HTTP_204_NO_CONTENT)
def remove_friend(
    friend_user_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    if friend_user_id == current_user.id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Cannot remove yourself.')

    low, high = friendship_pair(current_user.id, friend_user_id)
    friendship = db.scalar(
        select(Friendship).where(Friendship.user_low_id == low, Friendship.user_high_id == high)
    )

    if friendship is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Friendship not found.')

    db.delete(friendship)
    db.commit()
    return None
