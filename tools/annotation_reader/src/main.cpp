#include <getopt.h>
#include <iostream>

#include "annotation_reader.hpp"

static void printHelp() {
    std::cout << "Usage: ./annotation_reader -a <annotation.txt>" << std::endl;
}

int main(int argc, char **argv) {
    std::string inputFile;

    int opt;
    while ((opt = getopt(argc, argv, "a:")) != -1) {
        switch (opt) {
            case 'a': {
                inputFile = optarg;
                break;
            }
            default: {
                std::cout << "Unknown option: -" << opt << "!" << std::endl;
                printHelp();
                break;
            }
        }
    }

    if (inputFile.empty()) {
        std::cout << "You need to specify a input file!" << std::endl;
        printHelp();
        return 1;
    }

    annotation_reader reader(inputFile);

    if (!reader.good()) {
        return 2;
    }

    std::vector<Packet> packets;
    reader.parse(packets);

    for (decltype(packets.size()) i = 0; i < packets.size(); ++i) {
        std::cout << "Packet " << (i + 1) << "/" << packets.size() << ": "
                  << packets[i] << std::endl;
    }

    return 0;
}
