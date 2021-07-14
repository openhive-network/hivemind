Took post object and outputs bridge-api normalized version, but at the moment there is no fat node that would be source of unnormalized posts.
Result is basically the same as bridge.get_post.
Depracated.

method: "bridge.normalize_post"
params:
{
  "post": {

    "author":"{author}" + "permlink::"{permlink}",

       mandatory, point to valid post; rest of parameters are irrelevant

  }
}