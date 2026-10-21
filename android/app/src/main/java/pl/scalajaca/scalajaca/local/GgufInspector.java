package pl.scalajaca.scalajaca.local;

import java.io.File;
import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.charset.StandardCharsets;
import java.nio.ByteBuffer;
import java.nio.charset.CodingErrorAction;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Strukturalny preflight przed natywnym parserem. Nie wykonuje szablonu z GGUF. */
public final class GgufInspector {
    public static final long MAX_FILE = 3L * 1024 * 1024 * 1024;
    private static final long MAX_HEADER = 64L * 1024 * 1024;
    public static final class Info {
        public final String name, profile;
        public final int tensors;
        Info(String name, String profile, int tensors) { this.name = name; this.profile = profile; this.tensors = tensors; }
    }
    private static final class Span {
        final long start, end;
        Span(long start, long end) { this.start = start; this.end = end; }
    }
    private final RandomAccessFile in;
    private final long length;
    private final BooleanSupplier cancelled;
    private GgufInspector(RandomAccessFile in, BooleanSupplier cancelled) throws IOException {
        this.in = in; this.length = in.length(); this.cancelled = cancelled;
    }
    private IOException invalid() { return new IOException("invalid_gguf"); }
    private void check() throws IOException {
        if (cancelled.getAsBoolean()) throw new IOException("cancelled");
        if (in.getFilePointer() > MAX_HEADER) throw invalid();
    }
    private long u64() throws IOException {
        check(); long value = Long.reverseBytes(in.readLong());
        if (value < 0) throw invalid(); return value;
    }
    private int u32() throws IOException {
        check(); int value = Integer.reverseBytes(in.readInt());
        if (value < 0) throw invalid(); return value;
    }
    private void skip(long bytes) throws IOException {
        check(); long end;
        try { end = Math.addExact(in.getFilePointer(), bytes); } catch (ArithmeticException ex) { throw invalid(); }
        if (bytes < 0 || end > length || end > MAX_HEADER) throw invalid();
        in.seek(end);
    }
    private String string(int max) throws IOException {
        long bytes = u64();
        if (bytes > max || bytes > length - in.getFilePointer()) throw invalid();
        byte[] buffer = new byte[(int)bytes]; in.readFully(buffer);
        try { return StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(buffer)).toString(); }
        catch (java.nio.charset.CharacterCodingException ex) { throw invalid(); }
    }
    private Object value(int type, boolean retain) throws IOException {
        switch (type) {
            case 0: case 1: { int v = in.readUnsignedByte(); return retain ? (long)v : null; }
            case 2: case 3: { int v = Short.reverseBytes(in.readShort()) & 65535; return retain ? (long)v : null; }
            case 4: case 5: { long v = Integer.toUnsignedLong(Integer.reverseBytes(in.readInt())); return retain ? v : null; }
            case 6: skip(4); return null;
            case 7: skip(1); return null;
            case 8: if (retain) return string(4096); else { skip(u64()); return null; }
            case 9: {
                int element = u32(); long count = u64();
                if (count > 2000000 || element == 9 || element < 0 || element > 12) throw invalid();
                if (element == 8) {
                    for (long i = 0; i < count; i++) skip(u64());
                } else {
                    int[] widths = {1,1,2,2,4,4,4,1,0,0,8,8,8};
                    skip(count * widths[element]);
                }
                return null;
            }
            case 10: case 11: { long v = u64(); return retain ? v : null; }
            case 12: skip(8); return null;
            default: throw invalid();
        }
    }
    private Info read() throws IOException {
        if (length < 32 || length > MAX_FILE || in.readInt() != 0x47475546) throw invalid();
        int version = u32(); if (version != 2 && version != 3) throw invalid();
        long tensorCount = u64(), keyCount = u64();
        if (tensorCount < 1 || tensorCount > 4096 || keyCount > 4096) throw invalid();
        Map<String,Object> metadata = new HashMap<>();
        Set<String> keys = new HashSet<>();
        Set<String> selected = new HashSet<>(Arrays.asList("general.name", "general.basename", "general.size_label", "general.architecture", "general.alignment", "llama.block_count", "llama.embedding_length", "split.count"));
        for (long i = 0; i < keyCount; i++) {
            String key = string(512); if (!keys.add(key)) throw invalid();
            int type = u32(); Object result = value(type, selected.contains(key));
            if (result != null && selected.contains(key)) metadata.put(key, result);
        }
        if (!"llama".equals(metadata.get("general.architecture"))) throw new IOException("unsupported_model");
        String name = String.valueOf(metadata.getOrDefault("general.name", ""));
        // Oficjalny MiniCPM5-2B Q4_K_M opisuje rozmiar w GGUF jako 2.6B.
        // Alias dotyczy wyłącznie dokładnej tożsamości i geometrii tego profilu.
        boolean officialTwoBAlias = name.equalsIgnoreCase("MiniCPM5 2.6B")
            && "MiniCPM5".equalsIgnoreCase(String.valueOf(metadata.get("general.basename")))
            && "2.6B".equalsIgnoreCase(String.valueOf(metadata.get("general.size_label")));
        boolean mentionsTwoBAlias = (name + " " + metadata.getOrDefault("general.basename", "") + " "
            + metadata.getOrDefault("general.size_label", "")).toLowerCase(Locale.ROOT).contains("2.6b");
        if (mentionsTwoBAlias && !officialTwoBAlias) throw new IOException("unsupported_model");
        String identity = (name + metadata.getOrDefault("general.basename", "") + metadata.getOrDefault("general.size_label", "")).toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9]", "");
        String profile = officialTwoBAlias ? "minicpm5_2b"
            : identity.contains("minicpm5") && identity.contains("1b") ? "minicpm5_1b"
            : identity.contains("minicpm5") && identity.contains("2b") ? "minicpm5_2b" : null;
        if (profile == null) throw new IOException("unsupported_model");
        long layers = number(metadata, "llama.block_count", 0), embedding = number(metadata, "llama.embedding_length", 0);
        if (officialTwoBAlias && (layers != 42 || embedding != 2048)) throw new IOException("unsupported_model");
        if (layers < 1 || layers > 64 || embedding < 1 || embedding > 4096 || number(metadata, "split.count", 1) != 1) throw invalid();
        long alignment = number(metadata, "general.alignment", 32);
        if (alignment < 1 || alignment > 4096 || (alignment & (alignment - 1)) != 0) throw invalid();
        List<Span> spans = new ArrayList<>(); Set<String> tensorNames = new HashSet<>();
        for (long i = 0; i < tensorCount; i++) {
            if (!tensorNames.add(string(512))) throw invalid();
            int dimensions = u32(); if (dimensions < 1 || dimensions > 4) throw invalid();
            long elements = 1, row = 0;
            for (int d = 0; d < dimensions; d++) {
                long size = u64(); if (size < 1 || size > 200000) throw invalid();
                if (d == 0) row = size;
                try { elements = Math.multiplyExact(elements, size); } catch (ArithmeticException ex) { throw invalid(); }
                if (elements > 1000000000L) throw invalid();
            }
            int type = u32(); long offset = u64();
            int block, bytes;
            switch (type) {
                case 0: block=1; bytes=4; break;
                case 1: case 30: block=1; bytes=2; break;
                case 8: block=32; bytes=34; break;
                case 12: block=256; bytes=144; break;
                case 14: block=256; bytes=210; break;
                default: throw new IOException("unsupported_quantization");
            }
            if (row % block != 0 || offset % alignment != 0) throw invalid();
            long end;
            try { end = Math.addExact(offset, Math.multiplyExact(elements / block, bytes)); } catch (ArithmeticException ex) { throw invalid(); }
            if (end > length) throw invalid(); spans.add(new Span(offset, end));
        }
        long dataStart = (in.getFilePointer() + alignment - 1) / alignment * alignment;
        spans.sort(Comparator.comparingLong(s -> s.start)); long previous = 0;
        for (Span span : spans) {
            if (span.start < previous || span.end > length - dataStart) throw invalid();
            previous = span.end;
        }
        return new Info(name, profile, (int)tensorCount);
    }
    private long number(Map<String,Object> metadata, String key, long fallback) throws IOException {
        Object value = metadata.get(key); if (value == null) return fallback;
        if (!(value instanceof Long)) throw invalid(); return (Long)value;
    }
    public static Info inspect(File file, BooleanSupplier cancelled) throws IOException {
        try (RandomAccessFile stream = new RandomAccessFile(file, "r")) { return new GgufInspector(stream, cancelled).read(); }
        catch (java.io.EOFException ex) { throw new IOException("invalid_gguf"); }
    }
}
