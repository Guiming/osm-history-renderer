/**
 * osm-history-render importer - main file
 *
 * the importer reads through a pbf-file and writes its the content to a
 * postgresql database. While doing this, bits of the data is copied to
 * memory as a cache. This data is later used to build geometries for
 * ways and relations.
 */

#include <getopt.h>

#include <osmium/diff_visitor.hpp>
#include <osmium/io/any_input.hpp>
#include <osmium/io/reader.hpp>

/**
 * include the importer-handler which contains the main importer-logic.
 */
#include "handler.hpp"

/**
 * entry point into the importer.
 */
int main(int argc, char *argv[]) {
    // local variables for the options/switches on the commandline
    std::string nodestore{"stl"};
    std::string dsn;
    std::string prefix{"hist_"};
    bool printDebugMessages = false;
    bool printStoreErrors = false;
    bool calculateInterior = false;
    bool showHelp = false;
    bool keepLatLng = false;

    // options configuration array for getopt
    const struct option long_options[] = {
        {"help",         no_argument, nullptr, 'h'},
        {"debug",        no_argument, nullptr, 'd'},
        {"store-errors", no_argument, nullptr, 'e'},
        {"interior",     no_argument, nullptr, 'i'},
        {"latlng",       no_argument, nullptr, 'l'},
        {"latlon",       no_argument, nullptr, 'l'},
        {"nodestore",    required_argument, nullptr, 'S'},
        {"dsn",          required_argument, nullptr, 'D'},
        {"prefix",       required_argument, nullptr, 'P'},
        {nullptr, 0, nullptr, 0}
    };

    // walk through the options
    while (true) {
        const int c = getopt_long(argc, argv, "hdeilS:D:P:", long_options, nullptr);
        if (c == -1) {
            break;
        }

        switch (c) {
            // show the help
            case 'h':
                showHelp = true;
                break;

            // enable debug messages
            case 'd':
                printDebugMessages = true;
                break;

            // enables errors from the node-store. Possibly many in
            // softcutted files because of incomplete reference
            // in the input
            case 'e':
                printStoreErrors = true;
                break;

            // calculate the interior-point and store it in the database
            case 'i':
                calculateInterior = true;
                break;

            // keep lat/lng ant don't transform it to mercator
            case 'l':
                keepLatLng = true;
                break;

            // set the nodestore
            case 'S':
                nodestore = optarg;
                break;

            // set the database dsn, check the postgres documentation for syntax
            case 'D':
                dsn = optarg;
                break;

            // set the table-prefix
            case 'P':
                prefix = optarg;
                break;
        }
    }

    // if help was requested or the filename is missing
    if (showHelp || argc - optind < 1) {
        // print a short description of the possible options
        std::cerr
            << "Usage: " << argv[0] << " [OPTIONS] OSMFILE\n"
            << "Options:\n"
            << "  -h|--help\n"
            << "       show this nice, little help message\n"
            << "  -d|--debug\n"
            << "       enable debug messages\n"
            << "  -e|--store-errors\n"
            << "       enables errors from the node-store. Possibly many in softcutted files\n"
            << "       because of incomplete reference in the input\n"
            << "  -i|--interior\n"
            << "       calculate the interior-point ans store it in the database\n"
            << "  -l|--latlng\n"
            << "       keep lat/lng ant don't transform to mercator\n"
            << "  -s|--nodestore\n"
            << "       set the nodestore type [defaults to '" << nodestore << "']\n"
            << "       possible values: \n"
            << "          stl    (needs more memory but is more robust and a little faster)\n"
            << "          sparse (needs much, much less memory but is still experimental)\n"
            << "  -D|--dsn\n"
            << "       set the database dsn, check the postgres documentation for syntax\n"
            << "  -P|--prefix\n"
            << "       set the table-prefix [defaults to '"  << prefix << "']\n";

        return 1;
    }

    osmium::io::File infile{argv[optind]};

    // create an instance of the import-handler
    std::unique_ptr<Nodestore> store;
    if (nodestore == "sparse") {
        store.reset(new NodestoreSparse());
    } else {
        store.reset(new NodestoreStl());
    }

    // create an instance of the import-handler
    ImportHandler handler{store.get()};

    // copy relevant settings to the handler
    if (dsn.size()) {
        handler.dsn(dsn);
    }
    if (prefix.size()) {
        handler.prefix(prefix);
    }
    handler.printDebugMessages(printDebugMessages);
    handler.printStoreErrors(printStoreErrors);
    handler.calculateInterior(calculateInterior);
    handler.keepLatLng(keepLatLng);

    handler.init();

    // read the input-file to the handler
    osmium::io::Reader reader{infile};
    osmium::apply_diff(reader, handler);

    handler.final();

    return 0;
}
