public class Hello {
    public static void main(String[] args) {
        System.out.println("OK:" + String.join("|", args));
        System.exit(3);
    }
}
