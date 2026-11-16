package com.fixloop.complaint;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class LocationPathMatcherTest {

    @Test
    void matchesExactAndNestedSubtreesWithOrWithoutTrailingSlashes() {
        assertThat(LocationPathMatcher.matchesScope("/bmu/boys-hostel-t1/room-204", "/bmu/boys-hostel-t1")).isTrue();
        assertThat(LocationPathMatcher.matchesScope("/bmu/boys-hostel-t1/", "/bmu/boys-hostel-t1")).isTrue();
        assertThat(LocationPathMatcher.matchesScope("/bmu/boys-hostel-t1", "/bmu/boys-hostel-t1/")).isTrue();
        assertThat(LocationPathMatcher.matchesScope("/bmu/dining/d-cafe", "/bmu")).isTrue();
    }

    @Test
    void doesNotMatchSiblingPathsSharingAStringPrefix() {
        assertThat(LocationPathMatcher.matchesScope("/bmu/boys-hostel-t10/room-1", "/bmu/boys-hostel-t1")).isFalse();
        assertThat(LocationPathMatcher.matchesScope("/bmu", "/bmu/dining")).isFalse();
        assertThat(LocationPathMatcher.matchesScope(null, "/bmu")).isFalse();
    }
}
