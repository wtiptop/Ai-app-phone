package pl.scalajaca.scalajaca.local;

import org.junit.*;
import org.junit.rules.TemporaryFolder;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import static org.junit.Assert.*;

public class GgufInspectorTest {
    @Rule public TemporaryFolder temporary = TemporaryFolder.builder().assureDeletion().build();
    private void u32(DataOutputStream out, int value) throws IOException { out.writeInt(Integer.reverseBytes(value)); }
    private void u64(DataOutputStream out, long value) throws IOException { out.writeLong(Long.reverseBytes(value)); }
    private void string(DataOutputStream out, String value) throws IOException {
        byte[] bytes=value.getBytes(StandardCharsets.UTF_8); u64(out,bytes.length);out.write(bytes);
    }
    private void text(DataOutputStream out,String key,String value) throws IOException {string(out,key);u32(out,8);string(out,value);}
    private void integer(DataOutputStream out,String key,int value) throws IOException {string(out,key);u32(out,4);u32(out,value);}
    private byte[] fixture(String name,String architecture,int type,long offset,int tensors,boolean duplicate) throws IOException {
        ByteArrayOutputStream buffer=new ByteArrayOutputStream();DataOutputStream out=new DataOutputStream(buffer);
        out.writeInt(0x47475546);u32(out,3);u64(out,tensors);u64(out,duplicate?5:4);
        text(out,"general.architecture",architecture);text(out,"general.name",name);
        integer(out,"llama.block_count",24);integer(out,"llama.embedding_length",1280);
        if(duplicate) text(out,"general.architecture",architecture);
        for(int i=0;i<tensors;i++){string(out,"test_"+i);u32(out,1);u64(out,32);u32(out,type);u64(out,offset);}
        while(buffer.size()%32!=0)out.writeByte(0);out.write(new byte[128*tensors]);return buffer.toByteArray();
    }
    private byte[] valid() throws IOException {return fixture("MiniCPM5 1B","llama",0,0,1,false);}
    private byte[] twoBAlias(String basename,String size,int layers,int embedding) throws IOException {
        ByteArrayOutputStream buffer=new ByteArrayOutputStream();DataOutputStream out=new DataOutputStream(buffer);
        out.writeInt(0x47475546);u32(out,3);u64(out,1);u64(out,6);
        text(out,"general.architecture","llama");text(out,"general.name","MiniCPM5 2.6B");
        text(out,"general.basename",basename);text(out,"general.size_label",size);
        integer(out,"llama.block_count",layers);integer(out,"llama.embedding_length",embedding);
        string(out,"test");u32(out,1);u64(out,32);u32(out,0);u64(out,0);
        while(buffer.size()%32!=0)out.writeByte(0);out.write(new byte[128]);return buffer.toByteArray();
    }
    private File write(byte[] bytes) throws IOException {File file=temporary.newFile();Files.write(file.toPath(),bytes);return file;}
    private String hash(byte[] bytes) throws Exception {StringBuilder hex=new StringBuilder();for(byte b:MessageDigest.getInstance("SHA-256").digest(bytes))hex.append(String.format(Locale.ROOT,"%02x",b&255));return hex.toString();}
    private void rejects(byte[] bytes,String code) throws IOException {
        try {GgufInspector.inspect(write(bytes),()->false);fail("Nie odrzucono pliku");}
        catch(IOException ex){assertEquals(code,ex.getMessage());}
    }
    @Test public void readsStructuralMetadata() throws IOException {GgufInspector.Info info=GgufInspector.inspect(write(valid()),()->false);assertEquals("minicpm5_1b",info.profile);assertEquals(1,info.tensors);}
    @Test public void acceptsTwoBProfile() throws IOException {assertEquals("minicpm5_2b",GgufInspector.inspect(write(fixture("MiniCPM5 2B","llama",0,0,1,false)),()->false).profile);}
    @Test public void acceptsOfficialTwoBSizeAlias() throws IOException {
        assertEquals("minicpm5_2b",GgufInspector.inspect(write(twoBAlias("MiniCPM5","2.6B",42,2048)),()->false).profile);
    }
    @Test public void rejectsUnrecognisedTwoBSizeAliasIdentityOrGeometry() throws IOException {
        rejects(twoBAlias("Other","2.6B",42,2048),"unsupported_model");
        rejects(twoBAlias("MiniCPM5","2.7B",42,2048),"unsupported_model");
        rejects(twoBAlias("MiniCPM5","2B",41,2560),"unsupported_model");
        rejects(twoBAlias("MiniCPM5 2B","2.6B",42,2048),"unsupported_model");
        rejects(twoBAlias("MiniCPM5","2.6B",41,2048),"unsupported_model");
        rejects(twoBAlias("MiniCPM5","2.6B",42,2560),"unsupported_model");
    }
    @Test public void rejectsMagic() throws IOException {byte[] b=valid();b[0]=0;rejects(b,"invalid_gguf");}
    @Test public void rejectsVersion() throws IOException {byte[] b=valid();b[4]=4;rejects(b,"invalid_gguf");}
    @Test public void boundsTensorCount() throws IOException {byte[] b=valid();Arrays.fill(b,8,16,(byte)127);rejects(b,"invalid_gguf");}
    @Test public void boundsMetadataCount() throws IOException {byte[] b=valid();Arrays.fill(b,16,24,(byte)127);rejects(b,"invalid_gguf");}
    @Test public void rejectsOtherArchitecture() throws IOException {rejects(fixture("MiniCPM5 1B","other",0,0,1,false),"unsupported_model");}
    @Test public void rejectsOtherFamily() throws IOException {rejects(fixture("Other model","llama",0,0,1,false),"unsupported_model");}
    @Test public void rejectsDuplicateKeys() throws IOException {rejects(fixture("MiniCPM5 1B","llama",0,0,1,true),"invalid_gguf");}
    @Test public void rejectsUnknownQuantization() throws IOException {rejects(fixture("MiniCPM5 1B","llama",63,0,1,false),"unsupported_quantization");}
    @Test public void rejectsBadQuantizationRow() throws IOException {rejects(fixture("MiniCPM5 1B","llama",12,0,1,false),"invalid_gguf");}
    @Test public void rejectsOffsetPastFile() throws IOException {rejects(fixture("MiniCPM5 1B","llama",0,4096,1,false),"invalid_gguf");}
    @Test public void rejectsOverlappingTensors() throws IOException {rejects(fixture("MiniCPM5 1B","llama",0,0,2,false),"invalid_gguf");}
    @Test public void rejectsTruncatedData() throws IOException {byte[] b=valid();rejects(Arrays.copyOf(b,b.length-1),"invalid_gguf");}
    @Test public void supportsInspectionCancellation() throws IOException {
        try {GgufInspector.inspect(write(valid()),()->true);fail();}catch(IOException ex){assertEquals("cancelled",ex.getMessage());}
    }
    @Test public void importsHashAndDeduplicates() throws Exception {
        LocalModelStore store=new LocalModelStore(temporary.newFolder());byte[] bytes=valid();String sha=hash(bytes);
        LocalModelStore.Model model=store.importFrom(new ByteArrayInputStream(bytes),sha,()->false);
        assertEquals(sha,model.id);assertEquals(bytes.length,model.bytes);assertEquals(1,store.list().size());
        assertEquals(sha,store.importFrom(new ByteArrayInputStream(bytes),sha,()->false).id);assertEquals(1,store.list().size());
        store.remove(sha);assertTrue(store.list().isEmpty());
    }
    @Test public void rejectsHashMismatchAndCleansTemporaryFile() throws Exception {
        File root=temporary.newFolder();LocalModelStore store=new LocalModelStore(root);
        try {store.importFrom(new ByteArrayInputStream(valid()),String.join("",Collections.nCopies(64,"0")),()->false);fail();}
        catch(IOException ex){assertEquals("hash_mismatch",ex.getMessage());}assertEquals(0,root.list().length);
    }
    @Test public void cancelledImportKeepsExistingModel() throws Exception {
        File root=temporary.newFolder();LocalModelStore store=new LocalModelStore(root);byte[] bytes=valid();
        String id=store.importFrom(new ByteArrayInputStream(bytes),"",()->false).id;AtomicInteger checks=new AtomicInteger();
        try {store.importFrom(new ByteArrayInputStream(bytes),"",()->checks.incrementAndGet()>1);fail();}
        catch(IOException ex){assertEquals("cancelled",ex.getMessage());}assertEquals(id,store.list().get(0).id);assertEquals(2,root.list().length);
    }
    @Test public void idCannotEscapePrivateDirectory() throws Exception {
        LocalModelStore store=new LocalModelStore(temporary.newFolder());
        try {store.remove("../outside");fail();}catch(IOException ex){assertEquals("invalid_model_id",ex.getMessage());}
    }
    @Test public void cleansOnlyManagedPartialAndOrphanFiles() throws Exception {
        File root=temporary.newFolder();LocalModelStore store=new LocalModelStore(root);
        File owner=new File(root,"user.gguf");assertTrue(owner.createNewFile());assertTrue(new File(root,"import-abcd.partial").createNewFile());
        assertTrue(new File(root,String.join("",Collections.nCopies(64,"a"))+".gguf").createNewFile());
        store.cleanPartialImports();assertTrue(owner.exists());assertEquals(1,root.list().length);
    }
    @Test public void importsRealOfficialModelWhenProvided() throws Exception {
        String path=System.getProperty("scalajaca.testModel");Assume.assumeNotNull(path);
        File original=new File(path);LocalModelStore store=new LocalModelStore(temporary.newFolder());
        try(InputStream source=new FileInputStream(original)){
            LocalModelStore.Model model=store.importFrom(source,"81b64d05a23b17b34c475f42b3e72fbde62d4b92cc34541f7a8031d0752deafa",()->false);
            assertEquals("minicpm5_1b",model.profile);assertEquals(688065920L,model.bytes);
            assertEquals(219,GgufInspector.inspect(store.modelFile(model.id),()->false).tensors);
            store.remove(model.id);assertTrue(store.list().isEmpty());assertTrue(original.exists());
        }
    }
    @Test public void importsRealOfficialTwoBWhenProvided() throws Exception {
        String path=System.getProperty("scalajaca.testModel2B");Assume.assumeNotNull(path);
        File original=new File(path);LocalModelStore store=new LocalModelStore(temporary.newFolder());
        try(InputStream source=new FileInputStream(original)){
            LocalModelStore.Model model=store.importFrom(source,"ec2d5801640099e97d8d7e8003ad4d81f336e757811f03a26173dddf386602fd",()->false);
            assertEquals("minicpm5_2b",model.profile);assertEquals(1561318368L,model.bytes);
            assertEquals(381,GgufInspector.inspect(store.modelFile(model.id),()->false).tensors);
            store.remove(model.id);assertTrue(store.list().isEmpty());assertTrue(original.exists());
        }
    }
}
