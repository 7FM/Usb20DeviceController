#pragma once

#include <vector>
#include <cstdint>
#include <type_traits>

template<typename T>
void setBit(T& data, unsigned int bitOffset, bool value) {
    data = (data & ~(1 << bitOffset)) | (static_cast<T>(value ? 1 : 0) << bitOffset);
}

template<typename T, typename V>
void setValue(T& data, unsigned int offset, V value) {
    V v_mask = static_cast<V>(-1);
    T mask = static_cast<T>(~(static_cast<std::make_unsigned<T>::type>(v_mask) << offset));
    data = (data & mask) | (static_cast<T>(value) << offset);
}

template<typename T>
bool getBit(const T& data, unsigned int bitOffset) {
    return data & (1 << bitOffset);
}

template<typename T, typename V>
V getValue(const T& data, unsigned int offset) {
    V v_mask = static_cast<V>(-1);
    T mask = static_cast<std::make_unsigned<T>::type>(v_mask);
    return static_cast<V>((data >> offset) & mask);
}

template<unsigned int EPs>
struct FIFOFillState
{
    struct EpFillState{
        std::vector<uint8_t> data;
        int writePointer;
    };

    EpFillState epState[EPs];
    bool prevCLK12;

    void reset() {
        for (auto& s: epState) {
            s.data.clear();
            s.writePointer = 0;
        }
        prevCLK12 = false;
    }
};

template<typename T, unsigned int EPs>
void fillFIFO(T* top, FIFOFillState<EPs>& s) {

    // bool posedge = !s.prevCLK12 && top->EP_CLK12;
    bool negedge = s.prevCLK12 && !top->EP_CLK12;

    if (negedge) {
        for (unsigned int i = 0; i < EPs; ++i) {
            auto &ep = s.epState[i];
            setBit(top->EP_OUT_fillTransDone_i, i, ep.writePointer == ep.data.size());
            setBit(top->EP_OUT_fillTransSuccess_i, i, ep.writePointer == ep.data.size());

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

template<unsigned int EPs>
struct FIFOEmptyState {

    struct EpEmptyState{
        std::vector<uint8_t> data;
        bool done;
        bool waited;
    };

    EpEmptyState epState[EPs];
    bool prevCLK12;

    void reset() {
        for (auto &s : epState) {
            s.data.clear();
            s.done = false;
            s.waited = false;
        }

        prevCLK12 = false;
    }
};

template<typename T, unsigned int EPs>
void emptyFIFO(T* top, FIFOEmptyState<EPs>& s) {
    // bool posedge = !s.prevCLK12 && top->EP_CLK12;
    bool negedge = s.prevCLK12 && !top->EP_CLK12;

    if (negedge) {
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
