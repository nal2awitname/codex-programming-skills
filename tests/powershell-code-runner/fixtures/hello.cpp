#include <iostream>
#include <string>

int main(int argc, char **argv) {
    std::string text = "OK:";
    for (int i = 1; i < argc; ++i) {
        if (i > 1) text += '|';
        text += argv[i];
    }
    std::cout << text << '\n';
    return 3;
}
