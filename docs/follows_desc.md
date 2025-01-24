Zadaie:
- opisać w hivemindowym readme jak działają follow, mute oraz reszta operacji typu nested custom_json,
- co się dzieje jak użytkownik to wykona, jak to wykonać,
- podać przykłady operacji, coś na wzór tego co jest już dla community ( communities.md ),
- napisać na to testy, po poznaniu działania tych mechanizmów

Co wiadomo:
- chainowe operacje zostają bez zmian,
- wszystkie operacje custom_json(nested) są interpretowane przez kod hivemind,
- działają dokładnie tak jak operacje dla `communities`,
- kleśniak zmienia zasadę działania dla niektórych operacji (`follow?`),
- tutaj podobno powiązane issue ( https://gitlab.syncad.com/hive/hivemind/-/issues/267 ),
- tabela hive_follows została rozdzielona na kilka mniejszych tabel,
- debug w hivemind_endpoints.bridge_api_get_relationship_between_accounts nic nie robi, 
- tutaj MR klesniak - postęp prac nad zmianą follow ( https://gitlab.syncad.com/hive/hivemind/-/merge_requests/819 ),
- tutaj communities.md (https://gitlab.syncad.com/hive/hivemind/-/blob/master/docs/communities.md) sporo opisane o nested_custom_json,
- sporo opisane w komentarzach w MR,
- operacje nested_custom_json:
```python
    Nothing = 0
    Mute = 1
    Blacklist = 2
    Unblacklist = 4
    Follow = 5
    FollowBlacklisted = 7  # Added for 'follow_blacklist'
    UnFollowBlacklisted = 8  # Added for 'unfollow_blacklist'
    FollowMuted = 9  # Added for 'follow_muted'
    UnfollowMuted = 10  # Added for 'unfollow_muted'
    ResetBlacklist = 11  # cancel all existing records of Blacklist type
    ResetFollowingList = 12  # cancel all existing records of Blog type
    ResetMutedList = 13  # cancel all existing records of Ignore type
    ResetFollowBlacklist = 14  # cancel all existing records of Follow_blacklist type
    ResetFollowMutedList = 15  # cancel all existing records of Follow_muted type
    ResetAllLists = 16  # cancel all existing records of all types
```
-
```python
    [] - state 0
    [blog] - state 1
    [ignore] - state 2
```

Dziwne mechanizmy:
- jest coś takiego jak pośrednia block_lista:
  - alice dodaje na block listę boba,
  - carol robi follow_blacklist na alice ( czyli przejmuje blacklist konta alice ),
  - carol właśnie blacklistuje boba ( pośrednio poprzez alice ),
  - chociaż w tabeli u carol nie widać, że blokuje boba.
-

User actions:
```
 {"type": "custom_json_operation", "value": {"id": "follow", "json": "[\"follow\",{\"follower\":\"flw0\",\"following\":\"flw1\",\"that\":[\"blog\"]}]", "required_auths": [], "required_posting_auths": ["flw0"]}}
 
 {"type": "custom_json_operation", "value": {"id": "follow", "json": "[\"follow\",{\"follower\":\"flw0\",\"following\":\"flw2\",\"what\":\"blog\"}]", "required_auths": [], "required_posting_auths": ["flw0"]}}
 
 {"type": "custom_json_operation", "value": {"id": "follow", "json": "[\"follow\",{\"following\":\"flw3\",\"what\":[\"blog\"]}]", "required_auths": [], "required_posting_auths": ["flw0"]}}
 
 {"type": "custom_json_operation", "value": {"id": "follow", "json": "[\"follow\",{\"follower\":\"flw0x\",\"following\":[],\"what\":[\"ignore\"]}]", "required_auths": [], "required_posting_auths": ["flw0x"]}}
 
 {"type": "custom_json_operation", "value": {"id": "follow", "json": "[\"follow\",{\"follower\":\"flw1x\",\"what\":[\"reset_all_lists\"]}]", "required_auths": [], "required_posting_auths": ["flw1x"]}}
```
Spostrzeżenia mzander'a:
Wydaje mi się, że to działa tak:

1) są trzy state'y
```
'': Action.Nothing,
'blog': Action.Blog,
'follow': Action.Blog,
'ignore': Action.Ignore
```

state 0 - konto follower NIE followuje konta i nie ignoruje following - może mieć na konto blacklisted, follow_blacklists, follow_muted (wywoływany state pustym arrayem [])

state 1 - konto follower followuje konta following - może mieć na konto blacklisted, follow_blacklists, follow_muted (wywoływany state [blog] ALBO [follow] (nie znalazłem takiego z użyciem [follow] ale tak wynika z tego co czytam))

state 2 - konto follower ma mute na konta following - może mieć na konto blacklisted, follow_blacklists, follow_muted (wywoływany state [ignore])

2) są 3 'listy' (?) blacklist, follow_blacklists, follow_muted - nie do końca rozumiem co robią - na logikę to biorę

```
'blacklist': Action.Blacklist,
'unblacklist': Action.Unblacklist,
'follow_blacklist': Action.Follow_blacklist,
'unfollow_blacklist': Action.Unfollow_blacklist,
'follow_muted': Action.Follow_muted,
'unfollow_muted': Action.Unfollow_muted
```

akcja blacklist ustawia kolumne blacklist = true, unblacklist ustawia na false

akcja follow_blacklist ustawia kolumne follow_blacklist = true, unfollow_blacklist ustawia na false

akcja follow_muted ustawia kolumne follow_muted = true, unfollow_muted ustawia na false

3) jest 6 resetów z czego:
- 3 analogicznie do 3 'list' resetują bool w odpowiedniej liście ALE - z tego co widziałem to resety szły na konta 'null' i 'hive.blog' - i wtedy bool na konto (np null) był ustawiony na TRUE (co jest trochę nie intuicyjne?)
```
'reset_blacklist': Action.Reset_blacklist,
'reset_follow_blacklist': Action.Reset_follow_blacklist,
'reset_follow_muted_list': Action.Reset_follow_muted_list,
```

- kolejne 3 odnoszą się do state (reset_following_list - odnosi się do state 1 (follow/blog), reset_muted_list - state 2 (ignore), reset_all_lists - state 0 (chyba?))

```
'reset_following_list': Action.Reset_following_list,
'reset_muted_list': Action.Reset_muted_list,
'reset_all_lists': Action.Reset_all_lists,
```

z tymi resetami jest największa niewiadoma i nie do końca rozumiem jak one się mają w 100% do state między kontami follower i following bo wszystkie resety jakie znalazłem (oprócz tego jednego reset_all_lists na gtg w pkt d) były na konta 'null' i 'hive.blog' - w szczególności że tak jak napisałem operacja na following 'all' w hivemind zapisana była jako following 'null'


state 0, blacklisted = false and follow_blacklists = false and !!!!!!!!!!!!follow_muted = TRUE !!!!!!!!!!!!
```
"{""type"": ""custom_json_operation"", ""value"": {""id"": ""follow"", ""json"": ""[\""follow\"",{\""follower\"":\""hive.samadi\"",\""following\"":\""all\"",\""what\"":[\""reset_follow_muted_list\""]}]"", ""required_auths"": [], ""required_posting_auths"": [""hive.samadi""]}}"	76242558	327459293173389586	25
```

ten reset_follow_muted_list na ALL sprawił że follow_muted jest true (?)
ALE - ze wględu na to że w operacji jest to jednak 'all' - zakładam że to akcja która ma wpływ na wszystkie konta (?)

4) Powyciągane przykłady:

a)  state 0, blacklisted = TRUE and follow_blacklists = false and follow_muted = false
```
"{""type"": ""custom_json_operation"", ""value"": {""id"": ""follow"", ""json"": ""[\""follow\"",{\""follower\"":\""themarkymark\"",\""following\"":[\""dosostenido\""],\""what\"":[\""blacklist\""]}]"", ""required_auths"": [], ""required_posting_auths"": [""themarkymark""]}}"	82352704	353702170417175314	22
"{""type"": ""custom_json_operation"", ""value"": {""id"": ""follow"", ""json"": ""[\""follow\"",{\""follower\"":\""themarkymark\"",\""following\"":[\""guest07\""],\""what\"":[\""blacklist\""]}]"", ""required_auths"": [], ""required_posting_auths"": [""themarkymark""]}}"	82352680	353702067337962002	28
"{""type"": ""custom_json_operation"", ""value"": {""id"": ""follow"", ""json"": ""[\""follow\"",{\""follower\"":\""nikv\"",\""following\"":[\""dodocat\""],\""what\"":[\""blacklist\""]}]"", ""required_auths"": [], ""required_posting_auths"": [""nikv""]}}"	82336276	353631612694432274	10
"{""type"": ""custom_json_operation"", ""value"": {""id"": ""follow"", ""json"": ""[\""follow\"",{\""follower\"":\""themarkymark\"",\""following\"":[\""hivegifbot\""],\""what\"":[\""blacklist\""]}]"", ""required_auths"": [], ""required_posting_auths"": [""themarkymark""]}}"	82305461	353499263277204754	5
"{""type"": ""custom_json_operation"", ""value"": {""id"": ""follow"", ""json"": ""[\""follow\"",{\""follower\"":\""themarkymark\"",\""following\"":[\""penguinpablo\""],\""what\"":[\""blacklist\""]}]"", ""required_auths"": [], ""required_posting_auths"": [""themarkymark""]}}"	82295825	353457876972351762	36
"{""type"": ""custom_json_operation"", ""value"": {""id"": ""follow"", ""json"": ""[\""follow\"",{\""follower\"":\""themarkymark\"",\""following\"":[\""arcange-es\""],\""what\"":[\""blacklist\""]}]"", ""required_auths"": [], ""required_posting_auths"": [""themarkymark""]}}"	82277360	353378570401219858	4
"{""type"": ""custom_json_operation"", ""value"": {""id"": ""follow"", ""json"": ""[\""follow\"",{\""follower\"":\""themarkymark\"",\""following\"":[\""vancouverdining\""],\""what\"":[\""blacklist\""]}]"", ""required_auths"": [], ""required_posting_auths"": [""themarkymark""]}}"	82236713	353203992865544978	22
"{""type"": ""custom_json_operation"", ""value"": {""id"": ""follow"", ""json"": ""[\""follow\"",{\""follower\"":\""themarkymark\"",\""following\"":[\""guest10\""],\""what\"":[\""blacklist\""]}]"", ""required_auths"": [], ""required_posting_auths"": [""themarkymark""]}}"	82220603	353134800942401810	9
"{""type"": ""custom_json_operation"", ""value"": {""id"": ""follow"", ""json"": ""[\""follow\"",{\""follower\"":\""themarkymark\"",\""following\"":[\""notable\""],\""what\"":[\""blacklist\""]}]"", ""required_auths"": [], ""required_posting_auths"": [""themarkymark""]}}"	82178673	352954712963690002	34
"{""type"": ""custom_json_operation"", ""value"": {""id"": ""follow"", ""json"": ""[\""follow\"",{\""follower\"":\""themarkymark\"",\""following\"":[\""cleangirl\""],\""what\"":[\""blacklist\""]}]"", ""required_auths"": [], ""required_posting_auths"": [""themarkymark""]}}"	82103528	352631967646232594	37
```

b) state 0, blacklisted = false and follow_blacklists = TRUE and follow_muted = false
```
"{""type"": ""custom_json_operation"", ""value"": {""id"": ""follow"", ""json"": ""[\""follow\"",{\""follower\"":\""fersonjase1\"",\""following\"":\""all\"",\""what\"":[\""reset_follow_blacklist\""]}]"", ""required_auths"": [], ""required_posting_auths"": [""fersonjase1""]}}"	76737257	329584009199751186	14
"{""type"": ""custom_json_operation"", ""value"": {""id"": ""follow"", ""json"": ""[\""follow\"",{\""follower\"":\""themarkymark\"",\""following\"":\""all\"",\""what\"":[\""reset_follow_blacklist\""]}]"", ""required_auths"": [], ""required_posting_auths"": [""themarkymark""]}}"	82298233	353468219253596178	25
"{""type"": ""custom_json_operation"", ""value"": {""id"": ""follow"", ""json"": ""[\""follow\"",{\""follower\"":\""dazzjazzz\"",\""following\"":\""all\"",\""what\"":[\""reset_follow_blacklist\""]}]"", ""required_auths"": [], ""required_posting_auths"": [""dazzjazzz""]}}"	82137266	352776871252855570	8
"{""type"": ""custom_json_operation"", ""value"": {""id"": ""follow"", ""json"": ""[\""follow\"",{\""follower\"":\""timothyleecress\"",\""following\"":\""all\"",\""what\"":[\""reset_follow_blacklist\""]}]"", ""required_auths"": [], ""required_posting_auths"": [""timothyleecress""]}}"	81444711	349802370177175570	16
```

(wyżej były operacje na konta null i hive.blog - z tego co widzę na nie są tylko wywoływane actions reset_follow_blacklist - efektem jest follow_blacklists = TRUE, na zwykłe konta jest wywoływane action follow_blacklist)

```
"{""type"": ""custom_json_operation"", ""value"": {""id"": ""follow"", ""json"": ""[\""follow\"",{\""follower\"":\""henruc\"",\""following\"":[\""hive.blog\"",\""plentyofphish\""],\""what\"":[\""follow_blacklist\""]}]"", ""required_auths"": [], ""required_posting_auths"": [""henruc""]}}"	64456733	276839560242032146	93
```

c) state 0, blacklisted = false and follow_blacklists = false and follow_muted = TRUE
```
"{""type"": ""custom_json_operation"", ""value"": {""id"": ""follow"", ""json"": ""[\""follow\"",{\""follower\"":\""radaquest\"",\""following\"":[\""hive.blog\"",\""plentyofphish\""],\""what\"":[\""follow_muted\""]}]"", ""required_auths"": [], ""required_posting_auths"": [""radaquest""]}}"	81274108	349069635871573010	2
"{""type"": ""custom_json_operation"", ""value"": {""id"": ""follow"", ""json"": ""[\""follow\"",{\""follower\"":\""cronos0\"",\""following\"":[\""hive.blog\"",\""plentyofphish\""],\""what\"":[\""follow_muted\""]}]"", ""required_auths"": [], ""required_posting_auths"": [""cronos0""]}}"	76497117	328552615753285650	0
```


(tu w operacji wyżej jest przykład operacji na DWA KONTA - radaquest dał follow_muted na hive.blog i plentyofphish)
```
"{""type"": ""custom_json_operation"", ""value"": {""id"": ""follow"", ""json"": ""[\""follow\"",{\""follower\"":\""snook\"",\""following\"":\""all\"",\""what\"":[\""reset_follow_muted_list\""]}]"", ""required_auths"": [], ""required_posting_auths"": [""snook""]}}"	80948815	347672513074955794	6
"{""type"": ""custom_json_operation"", ""value"": {""id"": ""follow"", ""json"": ""[\""follow\"",{\""follower\"":\""buzzer11\"",\""following\"":\""all\"",\""what\"":[\""reset_follow_muted_list\""]}]"", ""required_auths"": [], ""required_posting_auths"": [""buzzer11""]}}"	80464017	345590321519789074	4
"{""type"": ""custom_json_operation"", ""value"": {""id"": ""follow"", ""json"": ""[\""follow\"",{\""follower\"":\""hive.samadi\"",\""following\"":\""all\"",\""what\"":[\""reset_follow_muted_list\""]}]"", ""required_auths"": [], ""required_posting_auths"": [""hive.samadi""]}}"	76242558	327459293173389586	25
```

(tu following jest 'all' a w hivemind konto following jest wpisane 'null', jest więcej takich kont - w każdym przypadku gdzie jest 'all' - akcją jest reset_follow_muted_list a na pojedyńcze konta jest follow_muted )

d) reset_all_lists
```
"{""type"": ""custom_json_operation"", ""value"": {""id"": ""follow"", ""json"": ""[\""follow\"",{\""follower\"":\""labrat\"",\""following\"":[\""gtg\""],\""what\"":[\""reset_all_lists\""]}]"", ""required_auths"": [], ""required_posting_auths"": [""labrat""]}}"	75037245	322282513256946962	16
```
