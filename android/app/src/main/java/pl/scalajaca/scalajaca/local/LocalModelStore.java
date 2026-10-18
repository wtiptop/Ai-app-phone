package pl.scalajaca.scalajaca.local;

import java.io.*;
import java.security.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Pliki wyłącznie w prywatnym katalogu aplikacji; ID to SHA-256 treści. */
public final class LocalModelStore {
    public static final long RESERVE_BYTES = 256L * 1024 * 1024;
    private final File root;
    public static final class Model {
        public final String id, name, profile;
        public final long bytes;
        Model(String id, String name, String profile, long bytes) { this.id=id; this.name=name; this.profile=profile; this.bytes=bytes; }
    }
    public LocalModelStore(File root) throws IOException {
        this.root = root.getCanonicalFile();
        if (!this.root.isDirectory() && !this.root.mkdirs()) throw new IOException("storage");
    }
    private File file(String id, String suffix) throws IOException {
        if (!id.matches("[a-f0-9]{64}")) throw new IOException("invalid_model_id");
        File result = new File(root, id + suffix).getCanonicalFile();
        if (!root.equals(result.getParentFile())) throw new IOException("invalid_model_id");
        return result;
    }
    public File modelFile(String id) throws IOException {
        File result = file(id, ".gguf"); if (!result.isFile()) throw new IOException("missing_model"); return result;
    }
    public List<Model> list() throws IOException {
        List<Model> models = new ArrayList<>(); File[] files = root.listFiles();
        if (files == null) throw new IOException("storage");
        for (File entry : files) {
            if (!entry.getName().matches("[a-f0-9]{64}\\.properties")) continue;
            String id = entry.getName().substring(0,64); File gguf = file(id, ".gguf");
            if (!gguf.isFile()) continue;
            Properties props = new Properties(); try (InputStream in = new FileInputStream(entry)) { props.load(in); }
            String profile = props.getProperty("profile", "");
            if (!profile.equals("minicpm5_1b") && !profile.equals("minicpm5_2b")) continue;
            models.add(new Model(id, clean(props.getProperty("name", "MiniCPM")), profile, gguf.length()));
        }
        models.sort(Comparator.comparing(m -> m.id)); return models;
    }
    public Model get(String id) throws IOException {
        for (Model model : list()) if (model.id.equals(id)) return model;
        throw new IOException("missing_model");
    }
    private String clean(String name) { return name.replaceAll("[\\p{Cntrl}]", " ").substring(0, Math.min(name.length(),120)); }
    public Model importFrom(InputStream source, String expectedHash, BooleanSupplier cancelled) throws IOException {
        if (expectedHash != null && !expectedHash.isEmpty() && !expectedHash.matches("[a-fA-F0-9]{64}")) throw new IOException("invalid_hash");
        File temp = File.createTempFile("import-", ".partial", root), metaTemp = null;
        try {
            MessageDigest digest; try { digest = MessageDigest.getInstance("SHA-256"); } catch (NoSuchAlgorithmException ex) { throw new IOException("hash"); }
            long size = 0; byte[] buffer = new byte[128 * 1024];
            try (FileOutputStream out = new FileOutputStream(temp)) {
                while (true) {
                    if (cancelled.getAsBoolean()) throw new IOException("cancelled");
                    int count = source.read(buffer); if (count < 0) break; if (count == 0) continue;
                    size += count;
                    if (size > GgufInspector.MAX_FILE) throw new IOException("file_too_large");
                    if (root.getUsableSpace() < RESERVE_BYTES + count) throw new IOException("storage_space");
                    out.write(buffer,0,count); digest.update(buffer,0,count);
                }
                out.getFD().sync();
            }
            StringBuilder hex = new StringBuilder(); for (byte b : digest.digest()) hex.append(String.format(Locale.ROOT,"%02x", b & 255));
            String id = hex.toString();
            if (expectedHash != null && !expectedHash.isEmpty() && !id.equalsIgnoreCase(expectedHash)) throw new IOException("hash_mismatch");
            GgufInspector.Info info = GgufInspector.inspect(temp, cancelled);
            if (cancelled.getAsBoolean()) throw new IOException("cancelled");
            File target = file(id, ".gguf"), metadata = file(id, ".properties");
            if (target.exists() && metadata.exists()) return get(id);
            Properties props = new Properties(); props.setProperty("name", clean(info.name)); props.setProperty("profile", info.profile);
            metaTemp = File.createTempFile("metadata-", ".partial", root);
            try (FileOutputStream out = new FileOutputStream(metaTemp)) { props.store(out, "Scalajaca GGUF"); out.getFD().sync(); }
            if (target.exists() || !temp.renameTo(target)) throw new IOException("storage");
            if (!metaTemp.renameTo(metadata)) { if (!target.delete()) throw new IOException("storage"); throw new IOException("storage"); }
            return new Model(id, clean(info.name), info.profile, size);
        } finally {
            if (temp.exists() && !temp.delete()) temp.deleteOnExit();
            if (metaTemp != null && metaTemp.exists() && !metaTemp.delete()) metaTemp.deleteOnExit();
        }
    }
    public void remove(String id) throws IOException {
        File model = file(id, ".gguf"), meta = file(id, ".properties");
        if (model.exists() && !model.delete()) throw new IOException("storage");
        if (meta.exists() && !meta.delete()) throw new IOException("storage");
    }
    public void cleanPartialImports() throws IOException {
        File[] entries = root.listFiles(); if (entries == null) return;
        for (File entry : entries) {
            boolean partial = entry.getName().matches("(import-|metadata-).+\\.partial");
            boolean orphan = entry.getName().matches("[a-f0-9]{64}\\.gguf") && !file(entry.getName().substring(0,64), ".properties").isFile();
            if ((partial || orphan) && !entry.delete()) throw new IOException("storage");
        }
    }
}
