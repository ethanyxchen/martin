import os

enum Log {
    static let audio = Logger(subsystem: "dev.ethanchen.martin", category: "audio")
    static let transcription = Logger(subsystem: "dev.ethanchen.martin", category: "transcription")
    static let assistant = Logger(subsystem: "dev.ethanchen.martin", category: "assistant")
}
