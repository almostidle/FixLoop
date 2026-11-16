package com.fixloop.storage;

import java.util.Optional;

/** Bytes in, verified bytes out: the storage implementation owns the naming. */
public interface StorageBackend {

    /**
     * Writes {@code content} under {@code key}.
     *
     * @throws IllegalArgumentException if the key does not have the generated shape
     * @throws IllegalStateException    if the bytes could not be written
     */
    void store(String key, byte[] content);

    /**
     * Reads the stored bytes for {@code key}, or returns empty if the key is
     * missing or does not correspond to a stored object on this backend.
     *
     * @throws IllegalStateException if reading fails due to an unexpected I/O error
     */
    Optional<byte[]> load(String key);
}
