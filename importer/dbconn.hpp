/**
 * The importer populates a postgres-database. This class controls a
 * connection to the database.
 */

#ifndef IMPORTER_DBCONN_HPP
#define IMPORTER_DBCONN_HPP

#include <libpq-fe.h>

#include <iostream>
#include <istream>
#include <stdexcept>
#include <string>

/**
 * Controls a connection to the database
 */
class DbConn {
protected:

    PGconn *conn = nullptr;

public:

    /**
     * Delete the controller and disconnect
     */
    ~DbConn() noexcept {
        close();
    }

    /**
     * Connect the controller to a database specified by the dsn
     */
    void open(const std::string& dsn) {
        conn = PQconnectdb(dsn.c_str());

        if (PQstatus(conn) != CONNECTION_OK) {
            std::cerr << PQerrorMessage(conn) << "\n";
            throw std::runtime_error{"connection to database failed"};
        }

        // disable sync-commits
        //  see http://lists.openstreetmap.org/pipermail/dev/2011-December/023854.html
        PGresult *res = PQexec(conn, "SET synchronous_commit TO off;");

        // check, that the query succeeded
        if (PQresultStatus(res) != PGRES_COMMAND_OK) {
            // show the error message, close the connection and throw out
            std::cerr << PQerrorMessage(conn) << "\n";
            PQclear(res);
            PQfinish(conn);
            throw std::runtime_error{"setting synchronous_commit to off failed"};
        }

        PQclear(res);
    }

    /**
     * Close the connection with the database
     */
    void close() noexcept {
        if (!conn) {
            return;
        }

        PQfinish(conn);

        conn = nullptr;
    }

    /**
     * execute one or more sql statements
     */
    void exec(const std::string& cmd) {
        // execute the command
        PGresult *res = PQexec(conn, cmd.c_str());

        // check, that the query succeeded
        ExecStatusType status = PQresultStatus(res);
        if (status != PGRES_COMMAND_OK && status != PGRES_TUPLES_OK) {
            // show the error message, close the connection and throw out
            std::cerr << PQresultErrorMessage(res) << "\n";
            PQclear(res);
            throw std::runtime_error{"command failed"};
        }

        PQclear(res);
    }

    /**
     * read a .sql-file and execute it
     */
    void execfile(std::ifstream& f, const std::string& prefix) {
        // read the file
        std::string cmd((std::istreambuf_iterator<char>(f)),
                         std::istreambuf_iterator<char>());

        // Replace "hist_" with the given prefix
        const std::string target = "hist_";
        size_t pos = 0;
        while ((pos = cmd.find(target, pos)) != std::string::npos) {
            cmd.replace(pos, target.length(), prefix);
            pos += prefix.length(); // Move past the replaced part
        }
        
        // and execute it
        exec(cmd);
    }
};

#endif // IMPORTER_DBCONN_HPP
