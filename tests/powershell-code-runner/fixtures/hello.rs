fn main() {
    let values: Vec<String> = std::env::args().skip(1).collect();
    println!("OK:{}", values.join("|"));
    std::process::exit(3);
}
