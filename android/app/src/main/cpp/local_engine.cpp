#include "local_engine.h"
#include "llama.h"
#include "ggml-backend.h"
#include "json.h"
#include "jinja/lexer.h"
#include "jinja/parser.h"
#include "jinja/runtime.h"
#include "templates.h"
#include <algorithm>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>

namespace scalajaca {
static std::once_flag initialized;
static bool abort_decode(void * p) { return static_cast<Control *>(p)->stopped(); }
static std::string stop_reason(const Control & control) { return control.cancelled ? "cancelled" : "timeout"; }
static std::string piece(const llama_vocab * vocab, llama_token token) {
    if (token == LLAMA_TOKEN_NULL) return "";
    std::vector<char> bytes(256);
    int count = llama_token_to_piece(vocab, token, bytes.data(), (int)bytes.size(), 0, true);
    if (count < 0) { if (count < -65536) throw Failure("token"); bytes.resize(-count); count = llama_token_to_piece(vocab, token, bytes.data(), (int)bytes.size(), 0, true); }
    if (count < 0) throw Failure("token");
    return std::string(bytes.data(), count);
}
Result generate(const std::string & path, const std::string & profile, const std::string & messages,
                int context, int limit, Control & control, const std::function<void(const std::string &)> & emit) {
    if (context < 512 || context > 4096 || limit < 1 || limit > 512 || limit >= context || messages.size() > 65536) throw Failure("invalid_request");
    const char * source = profile == "minicpm5_1b" ? TEMPLATE_MINICPM_1B : profile == "minicpm5_2b" ? TEMPLATE_MINICPM_2B : nullptr;
    if (!source) throw Failure("unsupported_model");
    Result result;
    if (control.stopped()) { result.reason = stop_reason(control); return result; }
    std::call_once(initialized, [] {
        llama_log_set([](ggml_log_level, const char *, void *) {}, nullptr);
        ggml_log_set([](ggml_log_level, const char *, void *) {}, nullptr);
        llama_backend_init();
        ggml_backend_load_all();
    });
    auto model_params = llama_model_default_params();
    model_params.n_gpu_layers = 0;
    model_params.load_mode = LLAMA_LOAD_MODE_MMAP;
    model_params.use_extra_bufts = false; // Bez dodatkowej kopii wag do repackingu.
    model_params.progress_callback = [](float, void * p) { return !static_cast<Control *>(p)->stopped(); };
    model_params.progress_callback_user_data = &control;
    std::unique_ptr<llama_model, decltype(&llama_model_free)> model(llama_model_load_from_file(path.c_str(), model_params), llama_model_free);
    if (!model) {
        if (control.stopped()) { result.reason = stop_reason(control); return result; }
        throw Failure("model_load");
    }
    const auto * vocab = llama_model_get_vocab(model.get());
    auto input = common_json::parse(messages);
    if (!input.is_array() || input.empty() || input.size() > 128) throw Failure("invalid_request");
    for (const auto & msg : input) {
        const std::string role = msg.at("role").get<std::string>();
        if ((role != "user" && role != "assistant" && role != "system") || !msg.at("content").is_string()) throw Failure("invalid_request");
    }
    jinja::lexer lexer;
    auto ast = jinja::parse_from_tokens(lexer.tokenize(source));
    jinja::context template_context(source);
    common_json constants = common_json::object();
    constants["bos_token"] = piece(vocab, llama_vocab_bos(vocab));
    constants["eos_token"] = piece(vocab, llama_vocab_eos(vocab));
    constants["add_generation_prompt"] = true;
    constants["enable_thinking"] = false;
    constants["tools"] = common_json::array();
    jinja::global_from_json(template_context, constants, false);
    common_json payload = common_json::object(); payload["messages"] = input;
    jinja::global_from_json(template_context, payload, true);
    jinja::runtime runtime(template_context);
    auto parts = jinja::runtime::gather_string_parts(runtime.execute(ast));
    std::vector<llama_token> tokens;
    for (const auto & part : parts->as_string().parts) {
        int count = -llama_tokenize(vocab, part.val.data(), (int)part.val.size(), nullptr, 0, false, !part.is_input);
        if (count < 0 || tokens.size() + count + limit > (size_t)context) throw Failure("context_limit");
        if (count == 0) continue;
        size_t start = tokens.size(); tokens.resize(start + count);
        if (llama_tokenize(vocab, part.val.data(), (int)part.val.size(), tokens.data() + start, count, false, !part.is_input) != count) throw Failure("token");
    }
    if (tokens.empty()) throw Failure("invalid_request");
    result.input = (int)tokens.size();
    if (control.stopped()) { result.reason = stop_reason(control); return result; }
    auto context_params = llama_context_default_params();
    context_params.n_ctx = context;
    context_params.n_batch = 128;
    context_params.n_ubatch = 128;
    context_params.n_threads = std::max(1, std::min(4, (int)std::thread::hardware_concurrency()));
    context_params.n_threads_batch = context_params.n_threads;
    context_params.no_perf = true;
    std::unique_ptr<llama_context, decltype(&llama_free)> ctx(llama_init_from_model(model.get(), context_params), llama_free);
    if (!ctx) throw Failure("memory");
    llama_set_abort_callback(ctx.get(), abort_decode, &control);
    std::unique_ptr<llama_sampler, decltype(&llama_sampler_free)> sampler(llama_sampler_chain_init(llama_sampler_chain_default_params()), llama_sampler_free);
    if (!sampler) throw Failure("memory");
    llama_sampler_chain_add(sampler.get(), llama_sampler_init_top_p(0.95f, 1));
    llama_sampler_chain_add(sampler.get(), llama_sampler_init_temp(profile == "minicpm5_1b" ? 0.7f : 1.0f));
    llama_sampler_chain_add(sampler.get(), llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
    for (size_t pos = 0; pos < tokens.size(); pos += 128) {
        if (control.stopped()) { result.reason = stop_reason(control); return result; }
        const int count = (int)std::min<size_t>(128, tokens.size() - pos);
        if (llama_decode(ctx.get(), llama_batch_get_one(tokens.data() + pos, count)) != 0) {
            if (control.stopped()) { result.reason = stop_reason(control); return result; }
            throw Failure("decode");
        }
    }
    for (int i = 0; i < limit; i++) {
        if (control.stopped()) { result.reason = stop_reason(control); return result; }
        auto token = llama_sampler_sample(sampler.get(), ctx.get(), -1);
        if (llama_vocab_is_eog(vocab, token)) { result.reason = "stop"; return result; }
        emit(piece(vocab, token));
        result.output++;
        if (i + 1 == limit) break;
        if (llama_decode(ctx.get(), llama_batch_get_one(&token, 1)) != 0) {
            if (control.stopped()) { result.reason = stop_reason(control); return result; }
            throw Failure("decode");
        }
    }
    result.reason = "length"; return result;
}
}
