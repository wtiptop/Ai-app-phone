#include "local_engine.h"
#include "json.h"
#include <fstream>
#include <iostream>

int main(int argc, char **argv) {
    if (argc != 4) return 2;
    std::ifstream input(argv[2],std::ios::binary);
    std::string inputText((std::istreambuf_iterator<char>(input)),std::istreambuf_iterator<char>());
    common_json trials=common_json::parse(inputText), report=common_json::array();
    for(const auto &trial:trials) {
        common_json item=trial;
        std::string output;
        try {
            scalajaca::Control control;
            auto result=scalajaca::generate(argv[1],"minicpm5_2b",trial.at("turns").dump(),4096,trial.value("limit",160),control,
                [&](const std::string &part){output+=part;},true);
            item["output"]=output;item["inputTokens"]=result.input;item["outputTokens"]=result.output;item["finishReason"]=result.reason;
        } catch(const std::exception &error) {item["error"]=error.what();item["output"]=output;}
        report.push_back(item);
        std::ofstream saved(argv[3],std::ios::binary);saved<<report.dump_safe(2)<<"\n";saved.close();
        std::cout<<trial.at("id").get<std::string>()<<" finished\n"<<std::flush;
    }
    return 0;
}
