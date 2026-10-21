#include "local_engine.h"
#include <iostream>
int main(int argc, char ** argv) {
    if (argc < 2 || argc > 3) { std::cerr << "Podaj plik GGUF i opcjonalnie profil minicpm5_1b/minicpm5_2b.\n"; return 2; }
    const std::string profile = argc == 3 ? argv[2] : "minicpm5_1b";
    if (profile != "minicpm5_1b" && profile != "minicpm5_2b") return 2;
    try {
        scalajaca::Control stop;
        std::string text;
        auto result = scalajaca::generate(argv[1], profile, R"([{"role":"user","content":"Reply with only the single word: OK"}])", 2048, 128, stop,
            [&](const std::string & chunk) { text += chunk; });
        std::cout << "Powód: " << result.reason << "; wejście: " << result.input << "; wyjście: " << result.output << "\n" << text << "\n";
        if (text.empty() || result.input <= 0 || result.output <= 0 || result.reason != "stop") return 1;
        scalajaca::Control cancelled; cancelled.cancelled = true;
        auto no_work = scalajaca::generate(argv[1], profile, "[]", 2048, 16, cancelled, [&](const std::string &) { throw std::runtime_error("unexpected emission"); });
        if (no_work.reason != "cancelled" || no_work.output != 0) return 1;
        std::cout << "PASS: rzeczywista generacja i anulowanie przed uruchomieniem.\n"; return 0;
    } catch (const std::exception & ex) { std::cerr << "FAIL: " << ex.what() << "\n"; return 1; }
}
