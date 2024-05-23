"""muted reasons enum to be used across hivemind"""

MUTED_REASONS = {'MUTED_COMMUNITY_MODERATION': 0, 'MUTED_COMMUNITY_TYPE': 1, 'MUTED_PARENT': 2, 'MUTED_REPUTATION': 3, 'MUTED_ROLE_COMMUNITY': 4}

def encode_bitwise_mask(muted_reasons):
    mask = 0
    for number in muted_reasons:
        # Shift number by one to accommodate the 0 value
        mask |= 1 << number
    return mask


def decode_bitwise_mask(muted_reasons_mask):
    if not isinstance(muted_reasons_mask, int):
        raise ValueError("Input must be an integer")
    if muted_reasons_mask < 0:
        raise ValueError("Mask cannot be negative")

    muted_reasons = []
    for i in range(32):  # Assuming a 32-bit integer
        if muted_reasons_mask & (1 << i):
            muted_reasons.append(i)
    return muted_reasons
