// The assistant behind a thread. It streams its answer piece by piece; the consumer
// stops it by cancelling the task that reads the stream.
protocol AssistantRepository: Sendable {
    func reply(to prompt: String, hasKey: Bool, pace: Duration) -> AsyncStream<String>
}
