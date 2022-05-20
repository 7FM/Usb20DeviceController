#pragma once

#include <cstdint>
#include <type_traits>
#include <vector>

template <typename T> void setBit(T &data, unsigned int bitOffset, bool value) {
    data = (data & ~(1 << bitOffset)) |
           (static_cast<T>(value ? 1 : 0) << bitOffset);
}

template <typename T, typename V>
void setValue(T &data, unsigned int offset, V value) {
    V v_mask = static_cast<V>(-1);
    T mask = static_cast<T>(
        ~(static_cast<std::make_unsigned<T>::type>(v_mask) << offset));
    data = (data & mask) | (static_cast<T>(value) << offset);
}

template <typename T> bool getBit(const T &data, unsigned int bitOffset) {
    return data & (1 << bitOffset);
}

template <typename T, typename V = uint8_t>
V getValue(const T &data, unsigned int offset) {
    V v_mask = static_cast<V>(-1);
    T mask = static_cast<std::make_unsigned<T>::type>(v_mask);
    return static_cast<V>((data >> offset) & mask);
}

template <unsigned int EPs, class Impl, class EpState> class BaseFIFOState {
  public:
    template <class T> void reset(T *top) {
        for (auto &s : epState) {
            s.reset();
        }
        prevCLK12 = false;
        disable();
        static_cast<Impl *>(this)->do_reset(top);
    }

    void enable() { enabled = true; }
    void disable() { enabled = false; }

    bool isEnabled() { return enabled; }
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
    bool doneSent;
    unsigned int writePointer;

    void reset() {
        data.clear();
        doneSent = false;
        writePointer = 0;
    }

    bool isDone() const { return sentAllData() && doneSent; }

    bool sentAllData() const { return data.size() == writePointer; }
};

template <unsigned int EPs>
class FIFOFillState
    : public BaseFIFOState<EPs, FIFOFillState<EPs>, EpFillState> {
  public:
    template <class T> void do_reset(T *top) {
        for (unsigned int i = 0; i < EPs; ++i) {
            setBit(top->EP_OUT_fillTransDone_i, i, false);
            setBit(top->EP_OUT_fillTransSuccess_i, i, false);
            setBit(top->EP_OUT_dataValid_i, i, false);
        }
    }
};

template <typename T, unsigned int EPs>
void fillFIFO(T *top, FIFOFillState<EPs> &s) {

    // bool posedge = !s.prevCLK12 && top->EP_CLK12;
    bool negedge = s.prevCLK12 && !top->EP_CLK12;

    if (negedge && s.isEnabled()) {
        for (unsigned int i = 0; i < EPs; ++i) {
            auto &ep = s.epState[i];
            setBit(top->EP_OUT_fillTransDone_i, i, ep.sentAllData());
            setBit(top->EP_OUT_fillTransSuccess_i, i, ep.sentAllData());
            ep.doneSent = ep.sentAllData();

            setBit(top->EP_OUT_dataValid_i, i,
                   ep.writePointer < ep.data.size());
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

    void reset() {
        data.clear();
        done = false;
    }

    bool isDone() const { return done; }
};

template <unsigned int EPs>
class FIFOEmptyState
    : public BaseFIFOState<EPs, FIFOEmptyState<EPs>, EpEmptyState> {
  public:
    template <class T> void do_reset(T *top) {
        for (unsigned int i = 0; i < EPs; ++i) {
            setBit(top->EP_IN_popTransDone_i, i, false);
            setBit(top->EP_IN_popTransSuccess_i, i, false);
            setBit(top->EP_IN_popData_i, i, false);
        }
    }
};

template <typename T, unsigned int EPs>
void emptyFIFO(T *top, FIFOEmptyState<EPs> &s) {
    // bool posedge = !s.prevCLK12 && top->EP_CLK12;
    bool negedge = s.prevCLK12 && !top->EP_CLK12;

    if (negedge && s.isEnabled()) {
        for (unsigned int i = 0; i < EPs; ++i) {
            auto &ep = s.epState[i];

            ep.done = (ep.done || !getBit(top->EP_IN_dataAvailable_o, i));

            setBit(top->EP_IN_popTransDone_i, i, ep.done);
            setBit(top->EP_IN_popTransSuccess_i, i, ep.done);
            setBit(top->EP_IN_popData_i, i, !ep.done);

            if (!ep.done && getBit(top->EP_IN_dataAvailable_o, i)) {
                ep.data.push_back(getValue(top->EP_IN_data_o, i * 8));
            }
        }
    }

    s.prevCLK12 = top->EP_CLK12;
}
