# Espresso Cafe Tycoon: benchmark research

Research date: **30 October 2026**. The live Roblox API snapshot below was retrieved between **22:46:48.757950 and 22:46:49.015140 UTC** on that date. Player counts and votes change; these numbers describe that retrieval, not a permanent ranking.

## Selection and method

The benchmark screen requested for this project is **strictly more than 95% positive votes and a currently active playerbase**. Approval is calculated from raw votes as `100 * upVotes / (upVotes + downVotes)`, before rounding. Votes, concurrent players and lifetime visits are separate signals. They do not establish polish, completion, average session length, retention, or the cause of a game's success.

For each experience, resolve the public place ID through `https://apis.roblox.com/universes/v1/places/PLACE_ID/universe`, then retrieve universe metadata and votes:

- [Roblox metadata and concurrent-player snapshot](https://games.roblox.com/v1/games?universeIds=7094518649,9970645639,3494556606,1214576306,2092410051,10465457905,5423299514,5743895194)
- [Roblox upvote and downvote snapshot](https://games.roblox.com/v1/games/votes?universeIds=7094518649,9970645639,3494556606,1214576306,2092410051,10465457905,5423299514,5743895194)

These are live endpoints, so opening the links later can return newer values. The table preserves the checked-at snapshot.

| Experience | Place ID | Universe ID | Upvotes | Downvotes | Positive | Playing | Screen |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- |
| Restaurant Tycoon 3 | 119048529960596 | 7094518649 | 400,872 | 19,780 | **95.30%** | **7,211** | Qualifies |
| Run a Restaurant! | 77843161404023 | 9970645639 | 549,337 | 7,313 | **98.69%** | **4,259** | Qualifies |
| My Hello Kitty Cafe | 9346039031 | 3494556606 | 882,731 | 32,614 | **96.44%** | **236** | Qualifies |
| Restaurant Tycoon 2 | 3398014311 | 1214576306 | 1,343,421 | 100,062 | 93.07% | 1,227 | Below rating threshold |
| Retail Tycoon 2 | 5865858426 | 2092410051 | 515,954 | 67,818 | 88.38% | 1,070 | Below rating threshold |
| Brew Empire | 111726279948618 | 10465457905 | 1,959 | 371 | 84.08% | 0 | Below rating threshold; no players at retrieval |
| Coffee Please! | 15698756562 | 5423299514 | 3,856 | 3,223 | 54.47% | 0 | Below rating threshold; no players at retrieval |
| Coffee Shop Tycoon | 16709466859 | 5743895194 | 41,359 | 3,175 | 92.87% | 4 | Below rating threshold |

The lower-rated examples are documented to explain their exclusion from the requested benchmark set. Their exclusion is not a claim that every mechanic they contain is poor. A zero count is one instantaneous observation, not proof of permanent inactivity.

## Mechanics observed in the qualifying games

### Restaurant Tycoon 3

Its current [official experience description](https://www.roblox.com/games/119048529960596/Restaurant-Tycoon-3) advertises serving, cooking, building and upgrading, offline earnings, and a Halloween customer/event update. Metadata records its latest update as **30 October 2026, 16:21:47.623 UTC**.

The creator's [50-feature announcement](https://devforum.roblox.com/t/50-new-features-in-restaurant-tycoon-3%E2%AD%90/3636102) describes worker skill upgrades and player milestones. Roblox's [Ultraw creator spotlight](https://devforum.roblox.com/t/creator-spotlight-how-ultraw%E2%80%99s-love-for-food-became-a-trending-tycoon/3840933) explains the emphasis on active customer service and staff management. These are earlier design accounts, not newly released October 2026 features. Some DevForum pages required JavaScript during direct browsing; the cited indexed primary-source excerpts were used for those specific claims.

**Applicable design inference:** keep a satisfying manual service loop alongside staff automation; let successive upgrades address understandable service bottlenecks.

### Run a Restaurant!

Its [official experience description](https://www.roblox.com/games/77843161404023/Run-a-Restaurant) lists cooking and serving, building and decorating, farming crops, raising animals, hiring staff and offline income. Metadata records its latest update as **29 October 2026, 14:30:27.714 UTC**.

**Applicable design inference:** connected progression systems can create several reasons to keep playing. Espresso's initial build uses recipes, equipment, staff and café growth; a farming system is not implied or promised by this comparison.

### My Hello Kitty Cafe

Its [official experience description](https://www.roblox.com/games/9346039031/My-Hello-Kitty-Cafe) describes character helpers, drinks and sweets, a five-star café goal, and current event missions with decoration rewards. Metadata records its latest update as **26 October 2026, 03:54:37.900 UTC**.

The [official Sanrio overview](https://www.sanrio.com/pages/my-hello-kitty-cafe-roblox) documents café building, expansion, decorating, menu creation and character collection. It also mentions gacha; that monetization system is not part of Espresso's initial design.

**Applicable design inference:** café identity, visible growth and collectible cosmetic goals can complement earning money. Espresso uses its own branding and themes, without borrowing Sanrio characters or artwork.

## Conclusions and limits

There is no single formal tycoon feature standard established by this research. The recurring patterns are an earning loop, reinvestment, visible business growth, some automation and longer-term goals. The three qualifying games satisfy the requested public approval/activity screen; this research did not run their clients or inspect their private analytics.

The hypothesis for Espresso is that manual coffee service, meaningful upgrades, mastery goals and café expression can support enjoyable repeat sessions. No public metric above demonstrates that these features cause retention or that players typically remain for hours. Session-duration distribution, tutorial completion, first-purchase conversion, and return rates must be measured in Espresso after actual playtesting and release. See [GAME_DESIGN.md](GAME_DESIGN.md) for the scoped plan.
