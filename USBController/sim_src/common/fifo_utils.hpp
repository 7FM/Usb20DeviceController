#pragma once

#include <cstdint>
#include <type_traits>
#include <vector>

template <typename T>
void setBit(T &data, unsigned int bitOffset, bool value) {
    data = (data & ~(1 << bitOffset)) | (static_cast<T>(value ? 1 : 0) << bitOffset);
}

template <typename T, typename V>
void setValue(T &data, unsigned int offset, V value) {
    V v_mask = static_cast<V>(-1);
    T mask = static_cast<T>(~(static_cast<std::make_unsigned<T>::type>(v_mask) << offset));
    data = (data & mask) | (static_cast<T>(value) << offset);
}

template <typename T>
bool getBit(const T &data, unsigned int bitOffset) {
    return data & (1 << bitOffset);
}

template <typename T, typename V = uint8_t>
V getValue(const T &data, unsigned int offset) {
    V v_mask = static_cast<V>(-1);
    T mask = static_cast<std::make_unsigned<T>::type>(v_mask);
    return static_cast<V>((data >> offset) & mask);
}

template <unsigned int EPs, class Impl, class EpState>
class BaseFIFOState {
  public:
    BaseFIFOState() {
        reset();
    }

    void reset() {
        for (auto &s : epState) {
            s.reset();
        }
        prevCLK12 = false;
        disable();
        static_cast<Impl *>(this)->do_reset();
    }

    void enable() {
        enabled = true;
    }
    void disable() {
        enabled = false;
    }

    bool isEnabled() {
        return enabled;
    }
    bool anyDone() {
        bool done = false;
        for (const auto &s : epState) {
            done |= s.isDone();
        }
        return done;
    }
    bool allDone() {
        bool done = true;
        for (const auto &s : epState) {
            done &= s.isDone();
        }
        return done;
    }

  public:
    EpState epState[EPs];
    bool prevCLK12;

  private:
    bool enabled;
};

struct EpFillState {
    std::vector<uint8_t> data;
    unsigned int writePointer;

    void reset() {
        data.clear();
        writePointer = 0;
    }

    bool isDone() const {
        return data.size() == writePointer;
    }
};

template <unsigned int EPs>
class FIFOFillState : public BaseFIFOState<EPs, FIFOFillState<EPs>, EpFillState> {
  public:
    void do_reset() {
    }
};

template <typename T, unsigned int EPs>
void fillFIFO(T *top, FIFOFillState<EPs> &s) {

    // bool posedge = !s.prevCLK12 && top->EP_CLK12;
    bool negedge = s.prevCLK12 && !top->EP_CLK12;

    if (negedge && s.isEnabled()) {
        for (unsigned int i = 0; i < EPs; ++i) {
            auto &ep = s.epState[i];
            setBit(top->EP_OUT_fillTransDone_i, i, ep.isDone());
            setBit(top->EP_OUT_fillTransSuccess_i, i, ep.isDone());

            setBit(top->EP_OUT_dataValid_i, i, ep.writePointer < ep.data.size());
            if (ep.writePointer < ep.data.size()) {
                setValue(top->EP_OUT_data_i, i * 8, ep.data[ep.writePointer]);

                if (!getBit(top->EP_OUT_full_o, i)) {
                    ++ep.writePointer;
                }
            }
        }
    }

    s.prevCLK12 = top->EP_CLK12;
}

struct EpEmptyState {
    std::vector<uint8_t> data;
    bool done;
    bool waited;

    void reset() {
        data.clear();
        done = false;
        waited = false;
    }

    bool isDone() const {
        return done;
    }
};

template <unsigned int EPs>
class FIFOEmptyState : public BaseFIFOState<EPs, FIFOEmptyState<EPs>, EpEmptyState> {
  public:
    void do_reset() {
    }
};

template <typename T, unsigned int EPs>
void emptyFIFO(T *top, FIFOEmptyState<EPs> &s) {
    // bool posedge = !s.prevCLK12 && top->EP_CLK12;
    bool negedge = s.prevCLK12 && !top->EP_CLK12;

    if (negedge && s.isEnabled()) {
        for (unsigned int i = 0; i < EPs; ++i) {
            auto &ep = s.epState[i];

            bool prevDone = ep.done;
            ep.done = (ep.done || !getBit(top->EP_IN_dataAvailable_o, i));

            setBit(top->EP_IN_popTransDone_i, i, ep.done);
            setBit(top->EP_IN_popTransSuccess_i, i, ep.done);
            setBit(top->EP_IN_popData_i, i, !ep.done);

            if (!prevDone && ep.done) {
                ep.data.push_back(getValue(top->EP_IN_data_o, i * 8));
            }

            if (!ep.done) {
                if (ep.waited) {
                    ep.data.push_back(getValue(top->EP_IN_data_o, i * 8));
                }
                ep.waited = getBit(top->EP_IN_dataAvailable_o, i);
            }
        }
    }

    s.prevCLK12 = top->EP_CLK12;
}
