#pragma once
#include <atomic>
#include <chrono>
#include <functional>
#include <stdexcept>
#include <string>

namespace scalajaca {
static constexpr const char * ENGINE_COMMIT = "5aeac37a35b44fde4bdffaec9159f2fcb253b622";
struct Failure : std::runtime_error { explicit Failure(const std::string & code) : std::runtime_error(code) {} };
struct Control {
    std::atomic<bool> cancelled{false};
    const std::chrono::steady_clock::time_point deadline = std::chrono::steady_clock::now() + std::chrono::minutes(3);
    bool stopped() const { return cancelled.load() || std::chrono::steady_clock::now() >= deadline; }
};
struct Result { int input = 0, output = 0; std::string reason; };
Result generate(const std::string & path, const std::string & profile, const std::string & messages,
                int context, int limit, Control & control, const std::function<void(const std::string &)> & emit,
                bool source_grounded = false);
}
