/*
 * ZeroTier One - Network Virtualization Everywhere
 * Copyright (C) 2011-2016  ZeroTier, Inc.  https://www.zerotier.com/
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

// Read and write the same world and key formats as the original mkworld.
#include <cstdio>
#include <cstring>
#include <stdexcept>
#include <string>
#include <vector>
#include <nlohmann/json.hpp>

#include "node/World.hpp"
#include "osdep/OSUtils.hpp"

using namespace ZeroTier;
using json = nlohmann::json;

#if __has_include("node/ECC.hpp")
using WorldKey = ECC;
#else
using WorldKey = C25519;
#endif

static std::string readFile(const char *name)
{
    std::string data;
    if (!OSUtils::readFile(name, data) || data.empty())
        throw std::runtime_error(std::string("Missing or empty file: ") + name);
    return data;
}

static void writeFile(const char *name, const std::string &data)
{
    if (!OSUtils::writeFile(name, data))
        throw std::runtime_error(std::string("Cannot write ") + name);
}

static void validatePair(const WorldKey::Pair &key, const char *name)
{
    const auto challenge = WorldKey::generate();
    unsigned char fromPrivate[32], fromPublic[32];
    WorldKey::agree(key.priv, challenge.pub, fromPrivate, sizeof(fromPrivate));
    WorldKey::agree(challenge.priv, key.pub, fromPublic, sizeof(fromPublic));
    const auto signature = WorldKey::sign(key, fromPrivate, sizeof(fromPrivate));
    if (memcmp(fromPrivate, fromPublic, sizeof(fromPrivate)) ||
        !WorldKey::verify(key.pub, fromPrivate, sizeof(fromPrivate), signature))
        throw std::runtime_error(std::string("Invalid public/private key pair: ") + name);
}

static WorldKey::Pair readKey(const char *name)
{
    const std::string data = readFile(name);
    WorldKey::Pair key;
    if (data.size() != sizeof(key.pub.data) + sizeof(key.priv.data))
        throw std::runtime_error(std::string("Invalid key length: ") + name);
    memcpy(key.pub.data, data.data(), sizeof(key.pub.data));
    memcpy(key.priv.data, data.data() + sizeof(key.pub.data), sizeof(key.priv.data));
    validatePair(key, name);
    return key;
}

static void newKeys()
{
    if (OSUtils::fileExists("previous.c25519", false) || OSUtils::fileExists("current.c25519", false))
        throw std::runtime_error("World signing key already exists");
    const WorldKey::Pair key = WorldKey::generate();
    std::string data(reinterpret_cast<const char *>(key.pub.data), sizeof(key.pub.data));
    data.append(reinterpret_cast<const char *>(key.priv.data), sizeof(key.priv.data));
    writeFile("previous.c25519", data);
    writeFile("current.c25519", data);
}

static void generate()
{
    const auto previous = readKey("previous.c25519");
    const auto current = readKey("current.c25519");
    const json config = json::parse(readFile("moon.json"));
    std::vector<World::Root> roots;
    for (const auto &r : config.at("roots")) {
        World::Root root;
        root.identity = Identity(r.at("identity").get<std::string>().c_str());
        if (!root.identity || root.identity.hasPrivate())
            throw std::runtime_error("Invalid root public identity");
        for (const auto &ep : r.at("stableEndpoints"))
            root.stableEndpoints.emplace_back(ep.get<std::string>().c_str());
        if (root.stableEndpoints.empty())
            throw std::runtime_error("Missing stable endpoint");
        roots.push_back(root);
    }
    if (roots.empty())
        throw std::runtime_error("Missing root");
    // Preserve the timestamp, root order and signing keys used by legacy installations.
    World world = World::make(World::TYPE_PLANET, ZT_WORLD_ID_EARTH, 1567191349589ULL,
                              current.pub, roots, previous);
    Buffer<ZT_WORLD_MAX_SERIALIZED_LENGTH> bytes;
    world.serialize(bytes, true);
    if (!WorldKey::verify(previous.pub, bytes.data(), bytes.size(), world.signature()))
        throw std::runtime_error("Invalid previous signing key pair");
    Buffer<ZT_WORLD_MAX_SERIALIZED_LENGTH> serialized;
    world.serialize(serialized);
    writeFile("world.bin", std::string(reinterpret_cast<const char *>(serialized.data()), serialized.size()));
}

static World readWorld(const char *path)
{
    const auto data = readFile(path);
    Buffer<ZT_WORLD_MAX_SERIALIZED_LENGTH> bytes(data.data(), data.size());
    World world;
    if (world.deserialize(bytes, 0) != data.size() || !world)
        throw std::runtime_error("Invalid world file");
    return world;
}

static void verifyChain(const World &world, const WorldKey::Public &signer,
                        const WorldKey::Public &successor, bool requirePublishedKeys)
{
    const auto &next = world.updatesMustBeSignedBy();
    Buffer<ZT_WORLD_MAX_SERIALIZED_LENGTH> bytes;
    world.serialize(bytes, true);
    const bool signedBySigner = WorldKey::verify(signer, bytes.data(), bytes.size(), world.signature());
    const bool trustsSuccessor = !memcmp(next.data, successor.data, sizeof(next.data));
    if (signedBySigner && trustsSuccessor)
        return;
    // A rotation can be staged before it is published. The existing world's
    // authorized next signer must be the signing key in the new configuration.
    const bool staged = memcmp(signer.data, successor.data, sizeof(next.data)) &&
                        !memcmp(next.data, signer.data, sizeof(next.data));
    if (!requirePublishedKeys && staged)
        return;
    throw std::runtime_error("World signature or successor key does not match signing material");
}

static void verifyWorldKeys(const char *path, bool restoringCopy)
{
    const World world = readWorld(path);
    if (world.type() != World::TYPE_PLANET || world.id() != ZT_WORLD_ID_EARTH)
        throw std::runtime_error("Expected an Earth Planet");
    verifyChain(world, readKey("previous.c25519").pub, readKey("current.c25519").pub, restoringCopy);
}

template <size_t Size>
static void readHexKey(const json &config, const char *name, unsigned char (&key)[Size])
{
    const auto hex = config.at(name).get<std::string>();
    if (hex.size() != Size * 2 || Utils::unhex(hex.c_str(), key, Size) != Size)
        throw std::runtime_error(std::string("Invalid Moon key: ") + name);
}

static void verifyMoon(const char *path, bool generated)
{
    const World world = readWorld(path);
    if (world.type() != World::TYPE_MOON)
        throw std::runtime_error("Expected a Moon");
    const auto config = json::parse(readFile("moon.json"));
    WorldKey::Pair signing;
    WorldKey::Public successor;
    readHexKey(config, "signingKey", signing.pub.data);
    readHexKey(config, "signingKey_SECRET", signing.priv.data);
    readHexKey(config, "updatesMustBeSignedBy", successor.data);
    validatePair(signing, "moon.json");
    verifyChain(world, signing.pub, successor, generated);
}

static json inspect(const char *path)
{
    const World world = readWorld(path);
    json roots = json::array();
    for (const auto &root : world.roots()) {
        char identity[ZT_IDENTITY_STRING_BUFFER_LENGTH];
        json endpoints = json::array();
        for (const auto &ep : root.stableEndpoints) {
            char address[64];
            endpoints.push_back(ep.toString(address));
        }
        roots.push_back({{"identity", root.identity.toString(false, identity)}, {"stableEndpoints", endpoints}});
    }
    return {{"worldType", world.type() == World::TYPE_PLANET ? "planet" : "moon"},
            {"id", world.id()}, {"roots", roots}};
}

int main(int argc, char **argv)
{
    try {
        if (argc == 2 && !strcmp(argv[1], "--new-keys")) {
            newKeys();
        } else if (argc == 3 && (!strcmp(argv[1], "--verify-keys") || !strcmp(argv[1], "--verify-key-copy"))) {
            verifyWorldKeys(argv[2], !strcmp(argv[1], "--verify-key-copy"));
        } else if (argc == 3 && (!strcmp(argv[1], "--verify-moon") || !strcmp(argv[1], "--verify-new-moon"))) {
            verifyMoon(argv[2], !strcmp(argv[1], "--verify-new-moon"));
        } else if (argc == 3 && !strcmp(argv[1], "--inspect")) {
            puts(inspect(argv[2]).dump().c_str());
        } else if (argc == 1 || (argc == 2 && (!strcmp(argv[1], "-j") || !strcmp(argv[1], "--json2bin")))) {
            generate();
        } else if (argc == 2 && (!strcmp(argv[1], "-b") || !strcmp(argv[1], "--bin2json"))) {
            writeFile("config.json", inspect("world.bin").dump(4));
        } else {
            fprintf(stderr, "Usage: mkworld [--new-keys | --inspect FILE | --verify-keys FILE | --verify-key-copy FILE | --verify-moon FILE | --verify-new-moon FILE | --json2bin | --bin2json]\n");
            return 1;
        }
        return 0;
    } catch (const std::exception &error) {
        fprintf(stderr, "mkworld: %s\n", error.what());
    } catch (...) {
        fprintf(stderr, "mkworld: invalid world data\n");
    }
    return 1;
}
