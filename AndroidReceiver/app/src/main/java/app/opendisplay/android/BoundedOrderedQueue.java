package app.opendisplay.android;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;

/** Small FIFO used to absorb short producer/consumer scheduling jitter. */
final class BoundedOrderedQueue<T> {
    private final int capacity;
    private final ArrayDeque<T> items = new ArrayDeque<>();

    BoundedOrderedQueue(int capacity) {
        if (capacity < 1) {
            throw new IllegalArgumentException("capacity must be positive");
        }
        this.capacity = capacity;
    }

    boolean offer(T item) {
        if (item == null || items.size() >= capacity) {
            return false;
        }
        items.addLast(item);
        return true;
    }

    T poll() {
        return items.pollFirst();
    }

    List<T> clearAndReturn() {
        List<T> removed = new ArrayList<>(items);
        items.clear();
        return removed;
    }

    void clear() {
        items.clear();
    }

    int size() {
        return items.size();
    }

    boolean isEmpty() {
        return items.isEmpty();
    }
}
