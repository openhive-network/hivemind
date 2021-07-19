Lists all subscribers with role, title and time of subscription for given community.

method: "bridge.list_subscribers"
params:
{
  "community":"{name}"

    mandatory, points to community

  "last":"{name}",

    optional, name of subscriber; paging mechanism (cuts out this and "higher" subscribers, depends on created at desc)

  "limit":{number},

    optional, range 1..100; default = 100

}