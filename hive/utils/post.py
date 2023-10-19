"""Methods for normalizing steemd post metadata."""
# pylint: disable=line-too-long,too-many-lines

import re


def mentions(body):
    """Given a post body, return proper @-mentioned account names."""
    # condenser:
    # /(^|[^a-zA-Z0-9_!#$%&*@＠\/]|(^|[^a-zA-Z0-9_+~.-\/#]))[@＠]([a-z][-\.a-z\d]+[a-z\d])/gi,
    # twitter:
    # validMentionPrecedingChars = /(?:^|[^a-zA-Z0-9_!#$%&*@＠]|(?:^|[^a-zA-Z0-9_+~.-])(?:rt|RT|rT|Rt):?)/
    # endMentionMatch = regexSupplant(/^(?:#{atSigns}|[#{latinAccentChars}]|:\/\/)/);
    matches = re.findall(
        '(?:^|[^a-zA-Z0-9_!#$%&*@\\/])' '(?:@)' '([a-zA-Z0-9][a-zA-Z0-9\\-.]{1,14}[a-zA-Z0-9])' '(?![a-z])', body
    )
    return {grp.lower() for grp in matches}
