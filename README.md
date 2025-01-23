# New Relic Godot Plugin

[New Relic](https://newrelic.com/) is a SaaS based observability platform that provides software monitoring and analytics for any technology. This addon allows developers to send useful data in the form of events, metrics, or logs from Godot developed games to New Relic for troubleshooting or game analysis. That data can then be used to create meaningful visualizations.

## Requirements
* [New Relic account/subscription](https://newrelic.com/signup)

## Installation & Configuration
1. Install the plugin from the Godot Asset Library, or copy the `newrelic-godot-plugin` directory into `addons` within your project root.
2. Go to `Project Settings -> Plugins` to enable.
3. Close Project Settings, and reopen. Go to General tab and search for a `Newrelic` section.
4. Login to your New Relic account, grab your [account id](https://docs.newrelic.com/docs/accounts/accounts-billing/account-structure/account-id/), and generate an [ingest (license) api key](https://docs.newrelic.com/docs/apis/intro-apis/new-relic-api-keys/#license-key) - Insert these values into the appropriate configuration fields within Godot Project Settings.
5. Start sending data to New Relic!


## Usage
The `newrelic` autoload is added to your project automatically when enabling the plugin. There are 3 types of methods available to use for forwarding data, as well as an exit method used to send any data before the game closes.

For a deeper understanding of each data type below - check out [this doc](https://docs.newrelic.com/docs/data-apis/understand-data/new-relic-data-types/)

### Events
An event is typically any point in time piece of data that represents something that occurred in a system. Common examples are level completed, final score of a game, or an unexpected error that occurred. Events are sent via the [Event API](https://docs.newrelic.com/docs/data-apis/ingest-apis/event-api/introduction-event-api/).

To send events, use `newrelic.send_event(<key>, <value>, <table>)` - The following table provides more detail into the function parameters.

| INPUT            | TYPE   | REQUIRED | DEFAULT | DESCRIPTION                                                                                                                                                                                                                                                                                |
| ---------------- | ------ | -------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| key        | string | TRUE   | ""      | The key of the event. This is what is queried on the New Relic side to obtain the value.                                                                                                                                                                                                                            |
| value          | string,int,bool | TRUE    | ""      | The actual value of the event, stored under the specified key.                                                                                                                                                                                                                 |
| table | string | TRUE    | ""      | Table that will contain all events to query within New Relic.                                                                                                                                  |
| includeDeviceInfo  | bool | FALSE    | FALSE      | Optional field to add device metadata to the event including OS name/version, isDebugBuild, processor name, gpu name/version |

#### Examples
```
newrelic.send_event("highScore", score, "MyHighScoreTable")
newrelic.send_event("levelComplete", true, "LevelCompletion", true)
```

Example queries of above events in New Relic:
```
SELECT * FROM MyHighScoreTable
SELECT latest(levelComplete) FROM LevelCompletion facet osType
```

Events can also be viewed under the [Data Explorer](https://docs.newrelic.com/docs/query-your-data/explore-query-data/browse-data/introduction-data-explorer/)

### Metrics
A metric is any pre-aggregated, numeric data point over a time window and is primarily used for long term storage (12+ months). For example, a sum of user logins may be aggregated over 1 minute time windows. Metrics are sent via the [Metric API](https://docs.newrelic.com/docs/data-apis/ingest-apis/metric-api/report-metrics-metric-api/).

To send metrics, use `newrelic.send_metric(<name>, <value>, <type>, <interval>, <attributes>, <includeDeviceInfo>)` - The following table provides more detail into available function parameters.

| INPUT            | TYPE   | REQUIRED | DEFAULT | DESCRIPTION                                                                                                                                                                                                                                                                                |
| ---------------- | ------ | -------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| name        | string | TRUE   | ""      | The name of the metric. Used as an identifer to query.                                                                                                                                                                                                                            |
| value          | int | TRUE    | ""      | The value of the metric expressed as an integer.                                                                                                                                                                                                               |
| type | string | FALSE    | `gauge`      | Type of metric - Can be one of: [`gauge`, `count`, `summary`]. See [Type Docs](https://docs.newrelic.com/docs/data-apis/understand-data/metric-data/metric-data-type/) for more information.                                                                                                                                  |
| interval  | int | FALSE    | 0      | Length of metric time window in milliseconds. Required only for `count` or `summary` types. |
| attributes  | Dictionary | FALSE    | {}      | Map of key-value pairs associated with the metric. |
| includeDeviceInfo  | bool | FALSE    | FALSE      | Optional field to add device metadata to the event including OS name/version, isDebugBuild, processor name, gpu name/version |

#### Examples
```
newrelic.send_metric("gauge_example_1", 1)
newrelic.send_metric("gauge_example_2", 2, "gauge", 0, {"key1": "value1", "key2": 12.3}, true)
newrelic.send_metric("count_example", 15, "count", 10000, {"key1": "value1", "key2": "value2"}, true)
newrelic.send_metric("summary_example", {"count": 5, "sum": 20, "min": 0.005, "max": 100}, "summary", 10000, {"key1": "value1", "key2": 12.3}, true)
```

Example query to view above metrics in New Relic:
```
SELECT * FROM Metric where metricName like '%example%'
```

Metrics can also be viewed under the [Data Explorer](https://docs.newrelic.com/docs/query-your-data/explore-query-data/browse-data/introduction-data-explorer/)

### Logs
A log is a detailed message that represents activity in a game to diagnose problems or gain deeper insight into game or system behavior. Logs are sent via the [Log API](https://docs.newrelic.com/docs/logs/log-api/introduction-log-api/).

To send logs, use `newrelic.send_log(<message>, <attributes>, <includeDeviceInfo>)` - The following table provides more detail into the function parameters.

| INPUT            | TYPE   | REQUIRED | DEFAULT | DESCRIPTION                                                                                                                                                                                                                                                                                |
| ---------------- | ------ | -------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| message        | string | TRUE   | ""      | The log message value. |
| attributes  | Dictionary | FALSE    | {}      | Map of key-value pairs associated with the log. |
| includeDeviceInfo  | bool | FALSE    | FALSE      | Optional field to add device metadata to the event including OS name/version, isDebugBuild, processor name, gpu name/version |

#### Examples
```
newrelic.send_log("test message 1")
newrelic.send_log("test message 2", {"key1": "value1", "key2": "value2"})
newrelic.send_log("test message 3", {"key1": "value1", "key2": "value2"}, true)
```

Example query of above logs in New Relic:
```
SELECT * FROM Log
```

Logs can also be viewed under the [Logs UI](https://docs.newrelic.com/docs/logs/get-started/get-started-log-management/)

### Exit
An exit method is provided to handle sending any final requests and flushing the request queue prior to any game close events. This should be used before any game exit calls (i.e - `SceneTree.quit()`) to ensure any outstanding data is sent.

```
await newrelic.handle_exit()
```

## Using Data in New Relic
[Dashboards](https://docs.newrelic.com/docs/query-your-data/explore-query-data/dashboards/introduction-dashboards/) can be built to easily visualize the data stored within New Relic. They are built with a SQL-like language called [NRQL](https://docs.newrelic.com/docs/nrql/get-started/introduction-nrql-new-relics-query-language/)

## Additional Notes
* The default max queue size (100) for http requests can be configured here depending on your performance needs.
* Compression is used to reduce the size of request bodies.
* It is expected to not send any sensitive or identifying player information. This plugin provides no safeguards for that.

## License
New Relic Godot Plugin is licensed under the [Apache 2.0](http://apache.org/licenses/LICENSE-2.0.txt) License.
