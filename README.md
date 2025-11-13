# SoC Design: CNN 가속기 설계 프로젝트

경희대학교 전자공학과 'EE470 SoC 설계' 과목의 기말 프로젝트에 대한 솔루션입니다.

## 1. 프로젝트 개요

**목표:** Zynq-7000 SoC 플랫폼(Arty Z7-20)을 활용하여, MNIST 데이터셋을 위한 LeNet-1 CNN 모델의 end-to-end 추론 시스템을 구축합니다.

**핵심 과제:**
* CNN의 핵심 연산(CONV, FC)을 FPGA 로직(PL)으로 구현.
* ARM 프로세서(PS)에서 실행되는 C 애플리케이션을 개발하여 PL 가속기를 제어.
* PS와 PL 간의 인터페이스는 AXI 프로토콜을 기반으로 통합합니다.

## 2. 개발 환경 및 사양

* **플랫폼:** Arty Z7-20 (Zynq-7000 SoC 탑재)
* **개발 도구:** Vivado & Vitis (2024.2)
* **타겟 모델:** LeNet-1 (Modified)
* **데이터셋:** MNIST (28x28 Grayscale, uint8)
* **가중치:** 제공되는 Quantized Weights (.h 파일) 사용

## 3. 시스템 아키텍처 (구상)

본 프로젝트는 강의자료에 제시된 아키텍처를 따릅니다.

* **PS (Processing System):**
    * ARM Cortex-A9 프로세서.
    * 전체 시스템 제어, DDR 메모리 및 데이터 관리 담당.
    * Vitis C 애플리케이션을 통해 PL 가속기 제어.
* **PL (Programmable Logic):**
    * FPGA 패브릭.
    * CNN의 연산 집약적 계층(CONV, FC)을 하드웨어 가속기로 구현.
    * 내부에는 Controller, Compute Unit 및 BRAM 기반 버퍼(Input/Weight/Output)가 포함될 예정.
* **인터페이스:**
    * PS-PL 간 통신은 AXI4-Lite를 기본으로 사용. (필요시 AXI-DMA/Stream 확장 고려)

## 4. 주요 설계 요구사항

* CONV (Convolution) 및 FC (Fully-Connected) 계층은 반드시 PL에서 실행되어야 합니다.
* BRAM을 활용한 버퍼링(buffering)이 구현되어야 합니다.
* 제공된 `main.c` 스켈레톤 코드를 기반으로 PS 사이드 애플리케이션을 완성해야 합니다.
* Vivado 합성과 구현을 완료하고 타이밍 리포트(WNS/TNS)를 확인하여 타이밍 클로저(timing closure)를 확보해야 합니다.

## 5. 평가 기준

프로젝트의 평가는 다음 세 가지 핵심 지표를 기준으로 합니다.

1.  **Latency (지연 시간):** 첫 PS-PL 트랜잭션부터 최종 결과 반환까지의 end-to-end 시간.
2.  **Accuracy (정확도):** PL에서 계산된 로짓(logits)을 기반으로 PS에서 계산된 Top-1 정확도 (%).
3.  **Hardware Utilization (하드웨어 사용률):** 최종 구현 후의 LUT, FF, BRAM, DSP 사용량.

## 6. 향후 개발 계획 (To-Do)

* [ ] **1. PL (Hardware) 설계:**
    * [ ] Verilog/VHDL 기반 CNN 코어 모듈(CONV, FC, Controller) RTL 작성
    * [ ] Vivado: AXI 인터페이스 기반 Custom IP 패키징
    * [ ] Vivado: Zynq PS를 포함한 전체 시스템 블록 디자인 구성
    * [ ] Vivado: 합성, 구현 및 타이밍 검증 후 `.xsa` 파일 Export
* [ ] **2. PS (Software) 개발:**
    * [ ] Vitis: `.xsa` 파일 임포트하여 플랫폼 생성
    * [ ] Vitis: `main.c` 작성 (데이터 로드, AXI를 통한 PL 제어, 결과 검증)
* [ ] **3. 통합 및 테스트:**
    * [ ] Arty Z7-20 보드에서 하드웨어 실행
    * [ ] UART 시리얼 출력을 통해 Latency 및 Accuracy 측정 및 검증
* [ ] **4. 문서화:**
    * [ ] 최종 보고서 및 발표 자료 작성