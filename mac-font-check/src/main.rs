//! A check for a Mac build machine: a scan of the installed fonts with the `fontdb` crate, and a report of what it finds: how many
//! fonts, whether the fonts every Mac has are there, whether a font the user installed is there, and which font files in the
//! scanned folders it does not list.

use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};

#[derive(Clone)]
#[allow(dead_code)]
struct SystemFont {
  family: String,
  full_name: String,
  postscript_name: String,
  style: String,
  path: String,
}

/// The style name of a face, from its weight and slant ("Regular", "Bold Italic", "Light" ...)
fn font_style_name(weight: u16, style: fontdb::Style) -> String {
  let weight_name = match ((weight + 50) / 100).clamp(1, 9) {
    1 => "Thin",
    2 => "ExtraLight",
    3 => "Light",
    4 => "Regular",
    5 => "Medium",
    6 => "SemiBold",
    7 => "Bold",
    8 => "ExtraBold",
    _ => "Black",
  };
  let slant = match style {
    fontdb::Style::Normal => None,
    fontdb::Style::Italic => Some("Italic"),
    fontdb::Style::Oblique => Some("Oblique"),
  };
  match slant {
    None => weight_name.to_owned(),
    Some(slant) if weight_name == "Regular" => slant.to_owned(),
    Some(slant) => format!("{weight_name} {slant}"),
  }
}

/// The fonts installed on the computer, as `fontdb` finds them.
fn installed_fonts() -> Vec<SystemFont> {
  let mut database = fontdb::Database::new();
  database.load_system_fonts();
  database
    .faces()
    .filter_map(|face| {
      let path = match &face.source {
        fontdb::Source::File(path) => path.clone(),
        fontdb::Source::SharedFile(path, _) => path.clone(),
        fontdb::Source::Binary(_) => return None,
      };
      let family = face.families.first()?.0.clone();
      let style = font_style_name(face.weight.0, face.style);
      Some(SystemFont { full_name: format!("{family} {style}"), family, postscript_name: face.post_script_name.clone(), style, path: path.to_string_lossy().into_owned() })
    })
    .collect()
}

/// every file under a folder
fn walk(dir: &Path, out: &mut Vec<PathBuf>) {
  let Ok(entries) = std::fs::read_dir(dir) else { return };
  for entry in entries.flatten() {
    let path = entry.path();
    match std::fs::metadata(&path) {
      Ok(meta) if meta.is_dir() => walk(&path, out),
      Ok(meta) if meta.is_file() => out.push(path),
      _ => {}
    }
  }
}

fn main() {
  let fonts = installed_fonts();
  let families: BTreeSet<&str> = fonts.iter().map(|font| font.family.as_str()).collect();
  println!("== what the scan lists ==");
  println!("faces listed:    {}", fonts.len());
  println!("families listed: {}", families.len());

  println!("\n== fonts every Mac has ==");
  let every_mac = ["Helvetica", "Helvetica Neue", "Menlo", "Arial", "Times New Roman", "Arial Hebrew"];
  for name in every_mac {
    println!("{:<18} {}", name, if families.contains(name) { "FOUND" } else { "not found" });
  }

  let home = std::env::var("HOME").unwrap_or_default();
  let user_dir = format!("{home}/Library/Fonts");
  let places: [(&str, String); 5] = [
    ("system (/System/Library/Fonts)", "/System/Library/Fonts".to_owned()),
    ("system, downloaded (/System/Library/AssetsV2)", "/System/Library/AssetsV2".to_owned()),
    ("all users (/Library/Fonts)", "/Library/Fonts".to_owned()),
    ("network (/Network/Library/Fonts)", "/Network/Library/Fonts".to_owned()),
    ("the user's own (~/Library/Fonts)", user_dir.clone()),
  ];
  println!("\n== where the listed faces come from ==");
  for (name, prefix) in &places {
    let count = fonts.iter().filter(|font| font.path.starts_with(prefix.as_str())).count();
    println!("{:<48} {}", name, count);
  }
  let elsewhere = fonts.iter().filter(|font| !places.iter().any(|(_, prefix)| font.path.starts_with(prefix.as_str()))).count();
  println!("{:<48} {}", "anywhere else", elsewhere);

  println!("\n== the user's own fonts that were listed ==");
  let own: BTreeSet<String> = fonts.iter().filter(|font| font.path.starts_with(user_dir.as_str())).map(|font| format!("{}  <-  {}", font.family, font.path)).collect();
  if own.is_empty() {
    println!("(none)");
  }
  for line in &own {
    println!("{line}");
  }

  println!("\n== the user's own faces, as listed: family | style | short name | file ==");
  let mut faces: Vec<String> = fonts
    .iter()
    .filter(|font| font.path.starts_with(user_dir.as_str()))
    .map(|font| format!("{} | {} | {} | {}", font.family, font.style, font.postscript_name, font.path.rsplit('/').next().unwrap_or("")))
    .collect();
  faces.sort();
  for line in &faces {
    println!("{line}");
  }

  println!("\n== font files in the scanned folders, by ending: files / files the scan listed ==");
  let listed: BTreeSet<&str> = fonts.iter().map(|font| font.path.as_str()).collect();
  let mut by_ending: BTreeMap<String, (usize, usize, Vec<String>)> = BTreeMap::new();
  let mut files = Vec::new();
  for (_, prefix) in &places {
    walk(Path::new(prefix), &mut files);
  }
  for file in &files {
    let ending = file.extension().map(|e| format!(".{}", e.to_string_lossy())).unwrap_or_else(|| "(no ending)".to_owned());
    let text = file.to_string_lossy().into_owned();
    // the scan keeps the real path of a file (links followed)
    let real = std::fs::canonicalize(file).map(|p| p.to_string_lossy().into_owned()).unwrap_or_else(|_| text.clone());
    let is_listed = listed.contains(text.as_str()) || listed.contains(real.as_str());
    let entry = by_ending.entry(ending).or_insert((0, 0, Vec::new()));
    entry.0 += 1;
    if is_listed {
      entry.1 += 1;
    } else if entry.2.len() < 4 {
      entry.2.push(text);
    }
  }
  for (ending, (count, read, examples)) in &by_ending {
    println!("{:<14} {:>5} / {:<5} {}", ending, count, read, if examples.is_empty() { String::new() } else { format!("not listed, e.g. {}", examples.join(" | ")) });
  }

  println!("\n== the user's own font files the scan did not list ==");
  let mut missed = 0;
  for file in files.iter().filter(|file| file.starts_with(&user_dir)) {
    let text = file.to_string_lossy().into_owned();
    let real = std::fs::canonicalize(file).map(|p| p.to_string_lossy().into_owned()).unwrap_or_else(|_| text.clone());
    if !listed.contains(text.as_str()) && !listed.contains(real.as_str()) {
      println!("{text}");
      missed += 1;
    }
  }
  if missed == 0 {
    println!("(none)");
  }

  // the verdict the job passes or fails on
  let user_font_files = files.iter().filter(|file| file.starts_with(&user_dir) && matches!(file.extension().and_then(|e| e.to_str()), Some("ttf") | Some("otf") | Some("ttc") | Some("otc"))).count();
  let mut problems = Vec::new();
  if fonts.is_empty() {
    problems.push("the scan listed no fonts at all".to_owned());
  }
  if cfg!(target_os = "macos") && !families.contains("Helvetica") {
    problems.push("Helvetica, which every Mac has, was not listed".to_owned());
  }
  if user_font_files > 0 && own.is_empty() {
    problems.push(format!("{user_font_files} font file(s) are in the user's own folder and none of them was listed"));
  }
  println!("\n== verdict ==");
  if problems.is_empty() {
    println!("OK: the scan lists the system's fonts{}", if user_font_files > 0 { " and the fonts the user installed" } else { " (no font is installed in the user's own folder here)" });
  } else {
    for problem in &problems {
      println!("PROBLEM: {problem}");
    }
    std::process::exit(1);
  }
}
