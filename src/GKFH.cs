// SPDX-License-Identifier: MIT
// Copyright (c) 2026 wittch
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Reflection;
#if !OVERLAY_TEST
using BepInEx;
using HarmonyLib;
#endif
using I2.Loc;

namespace GKFH {
 public static class PatchTargets {
  public static MethodInfo Resolve(Type owner,string name,params Type[] arguments) {
   var method=owner.GetMethod(name,BindingFlags.Public|BindingFlags.NonPublic|BindingFlags.Static|BindingFlags.Instance,null,arguments,null);
   if(method==null) throw new MissingMethodException(owner.FullName,name);
   return method;
  }
 }
 public sealed class Entry { public string EnglishHash; public string Korean; }
 public static class Overlay {
  public static string Hash(string value) {
   using(var sha=SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(value))).Replace("-", "");
  }
  public static Dictionary<string,Entry> Load(string path) {
   var rows=new Dictionary<string,Entry>(StringComparer.Ordinal);
   foreach(string line in File.ReadAllLines(path,Encoding.UTF8)) {
    if(line.Length==0) continue;
    string[] fields=line.Split('\t');
    if(fields.Length!=3) throw new InvalidDataException("Invalid translation record");
    string key=Encoding.UTF8.GetString(Convert.FromBase64String(fields[0]));
    var e=new Entry {EnglishHash=fields[1],Korean=Encoding.UTF8.GetString(Convert.FromBase64String(fields[2]))};
    rows.Add(key,e);
   }
   return rows;
  }
  public static int Apply(LanguageSourceData source,Dictionary<string,Entry> data) {
   int en=source.GetLanguageIndexFromCode("en-GB",true,false),ko=source.GetLanguageIndexFromCode("ko",true,false);
   if(en<0 || ko<0) return 0;
   var updates=new List<KeyValuePair<TermData,Entry>>();
   foreach(var term in source.mTerms) {
    Entry e;
    if(!data.TryGetValue(term.Term,out e)) continue;
    if(term.Languages==null || en>=term.Languages.Length || ko>=term.Languages.Length || Hash(term.Languages[en]??"")!=e.EnglishHash)
     throw new InvalidDataException("English source mismatch: "+term.Term);
    updates.Add(new KeyValuePair<TermData,Entry>(term,e));
   }
   foreach(var pair in updates) pair.Key.Languages[ko]=pair.Value.Korean;
   return updates.Count;
  }
 }
#if !OVERLAY_TEST
 [BepInPlugin("gkfont.frosthaven.korean","GKfont Frosthaven Korean","0.1.3")]
 [BepInProcess("Frosthaven.exe")]
 public sealed class Plugin : BaseUnityPlugin {
  internal static Plugin Instance;
  Dictionary<string,Entry> data;
  sealed class RuntimeEntry { public int Index; public string Text; }
  readonly Dictionary<TermData,RuntimeEntry> runtime=new Dictionary<TermData,RuntimeEntry>();
  readonly HashSet<LanguageSourceData> applied=new HashSet<LanguageSourceData>();
  Harmony harmony;
  void Awake() {
   try {
    string root=Path.GetDirectoryName(Info.Location);
    string[] expected=File.ReadAllLines(Path.Combine(root,"game-hashes.txt"));
    string game=BepInEx.Paths.GameRootPath;
    string[] paths={"Frosthaven_Data/Managed/Assembly-CSharp.dll","Frosthaven_Data/resources.assets"};
    for(int i=0;i<paths.Length;i++) {
     using(var sha=SHA256.Create()) using(var stream=File.OpenRead(Path.Combine(game,paths[i])))
      if(BitConverter.ToString(sha.ComputeHash(stream)).Replace("-","")!=expected[i]) throw new InvalidDataException("Unsupported game build");
    }
    data=Overlay.Load(Path.Combine(root,"korean.tsv"));
    var addSource=PatchTargets.Resolve(typeof(LocalizationManager),"AddSource",typeof(LanguageSourceData));
    var getTranslation=PatchTargets.Resolve(typeof(TermData),"GetTranslation",typeof(int),typeof(string),typeof(bool));
    Instance=this;
    harmony=new Harmony("gkfont.frosthaven.korean");
    harmony.Patch(addSource,prefix:new HarmonyMethod(typeof(Plugin).GetMethod("BeforeAddSource")));
    harmony.Patch(getTranslation,prefix:new HarmonyMethod(typeof(Plugin).GetMethod("BeforeTermTranslation")));
    foreach(var source in LocalizationManager.Sources) Apply(source);
    Logger.LogInfo("Loaded "+data.Count+" English-source translations. Game screen verification is pending.");
   } catch(Exception e) { Logger.LogError("Korean overlay disabled: "+e); Instance=null; }
  }
  public static void BeforeAddSource(LanguageSourceData __0) {
   if(Instance!=null) Instance.Apply(__0);
  }
  public static bool BeforeTermTranslation(TermData __instance,int __0,ref string __result) {
   RuntimeEntry entry;
   if(Instance!=null && Instance.runtime.TryGetValue(__instance,out entry) && __0==entry.Index) {
    __result=entry.Text; return false;
   }
   return true;
  }
  void Apply(LanguageSourceData source) {
   if(source==null || applied.Contains(source)) return;
   try {
    int count=Overlay.Apply(source,data);
    if(count>0) {
     int index=source.GetLanguageIndexFromCode("ko",true,false);
     foreach(var term in source.mTerms) {
      Entry entry;
      if(data.TryGetValue(term.Term,out entry)) runtime[term]=new RuntimeEntry {Index=index,Text=entry.Korean};
     }
     applied.Add(source); Logger.LogInfo("Applied Korean source entries: "+count);
    }
   } catch(Exception e) { Logger.LogError("Source unchanged: "+e); }
  }
  void Start() {
   if(Instance!=this) return;
   // The game already provides its Korean fonts and language setting.
   // The overlay only replaces Korean source values, leaving language choice to the player.
   LocalizationManager.LocalizeAll(true);
  }
 }
#endif
}
