from enum import IntEnum
class NotifyType(IntEnum):
    """Labels for notify `type_id` field."""

    # active
    new_community = 1
    set_role = 2
    set_props = 3
    set_title = 4
    mute_post = 5
    unmute_post = 6
    pin_post = 7
    unpin_post = 8
    flag_post = 9
    error = 10
    subscribe = 11

    reply = 12
    reply_comment = 13
    reblog = 14
    follow = 15
    mention = 16
    vote = 17

    # inactive
    # vote_comment = 16

    # update_account = 19
    # receive = 20
    # send = 21

    # reward = 22
    # power_up = 23
    # power_down = 24
    # message = 25