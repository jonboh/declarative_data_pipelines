use std::{collections::HashMap, fmt::Display, time::Duration};

use rdkafka::{
    consumer::{CommitMode, Consumer, StreamConsumer},
    message::BorrowedMessage,
    producer::{FutureProducer, FutureRecord},
    util::Timeout,
    ClientConfig, Message,
};
use serde_json::json;
use tracing::{error, info, warn};
use tracing_subscriber::{layer::SubscriberExt, Registry};

fn parse_message(message: &BorrowedMessage) -> Result<(Variable, f64, Duration), MessageError> {
    let payload: serde_json::Value = serde_json::from_str(
        message
            .payload_view::<str>()
            .ok_or("Message was empty")?
            .map_err(|e| format!("Error while deserializing message payload: {e}"))?,
    )
    .map_err(|e| format!("Message payload could not be parsed as JSON. Error: {e}"))?;

    let fields: &serde_json::Value = payload
        .get("fields")
        .ok_or("There wasn't a `fields` in the message payload.")?;
    let unix_nanos: u64 = payload
        .get("timestamp")
        .ok_or("There wasn't a value in the message payload.")?
        .as_u64()
        .ok_or("value could not be parsed as u64")?;
    let timestamp = Duration::new(
        unix_nanos / 1_000_000_000,
        (unix_nanos % 1_000_000_000) as u32,
    );
    if let Some(value) = fields.get("Temperature") {
        let temp = value.as_f64().ok_or("values must be f64")?;
        return Ok((Variable::Temperature, temp, timestamp));
    }
    if let Some(value) = fields.get("Pressure") {
        let pressure = value.as_f64().ok_or("values must be f64")?;
        return Ok((Variable::Pressure, pressure, timestamp));
    }
    if let Some(value) = fields.get("SlowSensor") {
        let measure = value.as_f64().ok_or("values must be f64")?;
        return Ok((Variable::SlowSensor, measure, timestamp));
    }
    Err(MessageError::Error("Unknown variable".to_string()))
}

struct ComputationResult {
    timestamp: Duration,
    abs_mean: f64,
    geo_mean: f64,
}

enum MessageError {
    Error(String),
}

#[derive(PartialEq, Eq, Hash, Clone, Copy)]
enum Variable {
    Temperature,
    Pressure,
    SlowSensor,
}

impl Display for Variable {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Variable::Temperature => write!(f, "Temperature"),
            Variable::Pressure => write!(f, "Pressure"),
            Variable::SlowSensor => write!(f, "SlowSensor"),
        }
    }
}

impl From<String> for MessageError {
    fn from(s: String) -> Self {
        Self::Error(s)
    }
}

impl From<&str> for MessageError {
    fn from(s: &str) -> Self {
        Self::Error(s.to_string())
    }
}

fn handle_message(
    m: &BorrowedMessage,
    state: &mut HashMap<Variable, f64>,
) -> Result<ComputationResult, MessageError> {
    let (var, value, time) = parse_message(m)?;
    state.insert(var, value);
    let temp = *state.entry(Variable::Temperature).or_insert(0.0);
    let pressure = *state.entry(Variable::Pressure).or_insert(0.0);
    let adjustment = *state.entry(Variable::SlowSensor).or_insert(0.0);
    let abs_mean = (temp.abs() + pressure.abs() + adjustment.abs()) / 3.0;
    let geo_mean = (temp.abs() * pressure.abs() * adjustment.abs()).cbrt();

    info!("Processed message: Key: {var} Value: {value}");
    Ok(ComputationResult {
        timestamp: time,
        abs_mean,
        geo_mean,
    })
}

async fn send(producer: &FutureProducer, percentiles_topic: &str, results: ComputationResult) {
    let send_requests = [("model1", results.abs_mean), ("model2", results.geo_mean)].map(
        |(name, value)| async move {
            match producer
                .send(
                    FutureRecord::<str, String>::to(percentiles_topic)
                        .payload(
                            &json!({
                                "name": name,
                                "value": value,
                                "timestamp": results.timestamp.as_nanos()
                            })
                            .to_string(),
                        )
                        .timestamp(
                            results
                                .timestamp
                                .as_millis()
                                .try_into()
                                .expect("milliseconds should always be expressable in i64"),
                        ),
                    Timeout::After(Duration::from_secs(30)),
                )
                .await
            {
                Ok(_) => info!("Message for [{name}={value}] sent"),
                Err(_) => error!("Failed to send message for [{name}={value}]"),
            }
        },
    );
    for fut in send_requests {
        fut.await;
    }
}

#[tokio::main]
async fn main() {
    let stdout_log = tracing_subscriber::fmt::layer().pretty();
    let subscriber = Registry::default().with(stdout_log);
    let subscriber = subscriber.with(tracing_subscriber::fmt::layer().with_ansi(false));
    tracing::subscriber::set_global_default(subscriber).expect("Unable to set global subscriber");

    let kafka_address =
        std::env::var("KAFKA_ADDRESS").expect("KAFKA_ADDRESS should be set to <ip>:<port>");

    let input_topic = "opc";
    let output_topic = "model";

    let consumer: StreamConsumer = ClientConfig::new()
        .set("group.id", "model")
        .set("bootstrap.servers", kafka_address.clone())
        .set("enable.auto.commit", "true")
        .set("auto.offset.reset", "latest")
        .create()
        .expect("Consumer creation failed");
    // Subscribe to a topic
    consumer
        .subscribe(&[input_topic])
        .expect("Can't subscribe to specified topic");

    let producer: &FutureProducer = &ClientConfig::new()
        .set("bootstrap.servers", kafka_address)
        .set("message.timeout.ms", "5000")
        .create()
        .expect("Producer creation error");

    let mut state = HashMap::<Variable, f64>::new();

    loop {
        let results = match consumer.recv().await {
            Err(e) => {
                warn!("Kafka error: {}", e);
                continue;
            }
            Ok(m) => match handle_message(&m, &mut state) {
                Ok(computation) => {
                    consumer.commit_message(&m, CommitMode::Async).unwrap();
                    computation
                }
                Err(MessageError::Error(msg)) => {
                    error!(msg);
                    continue;
                }
            },
        };
        send(producer, output_topic, results).await;
    }
}
