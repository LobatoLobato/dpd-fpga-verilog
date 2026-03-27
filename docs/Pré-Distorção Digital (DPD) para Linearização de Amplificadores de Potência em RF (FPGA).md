# Pré-Distorção Digital (DPD) para Linearização de Amplificadores de Potência em RF (FPGA)

## 1. Visão Geral do Projeto

Este projeto acadêmico, desenvolvido como Trabalho de Conclusão de Curso (TCC), foca na implementação de um sistema de Pré-Distorção Digital (DPD) para a linearização de Amplificadores de Potência (PA) em transmissores de radiofrequência (RF). O objetivo principal é compensar as não linearidades inerentes aos PAs quando operam próximos à saturação, garantindo a integridade do sinal transmitido e a eficiência espectral. A arquitetura proposta será implementada em um Field-Programmable Gate Array (FPGA) utilizando a linguagem de descrição de hardware Verilog, com validação por simulação digital completa.

## 2. Contexto e Motivação

Amplificadores de Potência são componentes cruciais em sistemas de comunicação sem fio, mas sua operação em regimes de alta eficiência (próximos à saturação) introduz não linearidades que geram distorção de sinal e espalhamento espectral. A Pré-Distorção Digital é uma técnica eficaz para mitigar esses efeitos, aplicando uma distorção inversa ao sinal de entrada do PA, de modo que a combinação PA-DPD apresente um comportamento linear. Este projeto visa explorar e implementar essa técnica em um ambiente digital reconfigurável (FPGA), otimizando o desempenho e a flexibilidade do sistema.

## 3. Arquitetura do Sistema

O sistema de DPD proposto é uma arquitetura digital robusta, projetada para processar sinais complexos em banda base no formato I/Q (In-phase e Quadrature). A arquitetura geral é composta pelos seguintes estágios:

*   **Interface de Entrada de Sinais I/Q**: Responsável pela recepção das amostras digitais dos sinais I/Q.
*   **Núcleo de DPD**: Implementa o algoritmo de pré-distorção, tipicamente baseado em um modelo polinomial com memória (Memory Polynomial), que aplica a distorção controlada ao sinal de entrada.
*   **Conversão Digital-Analógica Simulada (DAC)**: Representa a conversão do sinal digital para o domínio analógico antes de ser aplicado ao PA.
*   **Modelo Digital do Amplificador de Potência Não Linear**: Em vez de um PA físico, utiliza-se um modelo matemático digital que reproduz os efeitos de compressão de ganho, distorção de fase e efeitos de memória do amplificador real. Modelos como Memory Polynomial ou Rapp podem ser empregados.
*   **Conversão Analógico-Digital Simulada (ADC)**: Representa a conversão do sinal de saída do PA de volta ao domínio digital.
*   **Canal de Realimentação (Feedback)**: Coleta amostras do sinal distorcido após o PA, permitindo a comparação com o sinal original para a estimação dos coeficientes do DPD.

O diagrama de blocos simplificado da arquitetura é apresentado abaixo:

```mermaid
graph TD
    A[Sinal de Entrada I/Q] --> B{Núcleo DPD}
    B --> C[DAC Simulado]
    C --> D[Modelo PA Não Linear]
    D --> E[ADC Simulado]
    E --> F{Canal de Realimentação}
    F --> G[Comparador]
    G --> H[Estimação de Coeficientes (Software Externo)]
    H --> B
    E --> I[Sinal de Saída Linearizado]
```

## 4. Estimação e Atualização de Coeficientes

A estimação dos coeficientes complexos que caracterizam a função inversa do amplificador é realizada por um software externo (e.g., Python ou MATLAB). Este software recebe dados capturados do sinal de entrada e do sinal de saída do PA (via mecanismo de transferência digital, como DMA), calcula os coeficientes e os envia ao hardware FPGA. A atualização dos coeficientes no bloco DPD é feita através de uma interface de controle, como AXI-Lite, garantindo a adaptabilidade do sistema às variações do PA.

## 5. Implementação em FPGA

Todo o processamento em tempo real, incluindo o cálculo das bases não lineares, atrasos de memória, multiplicações complexas e acumulação dos termos do modelo, é realizado no FPGA. O sistema é projetado para suportar um fluxo contínuo de amostras I/Q, garantindo a operação em tempo real necessária para aplicações de RF.

### Tecnologias e Ferramentas

*   **Linguagem de Descrição de Hardware**: Verilog
*   **Plataforma de Hardware**: FPGA (a ser definida, e.g., Xilinx, Intel/Altera)
*   **Interface de Controle**: AXI-Lite
*   **Software de Estimação**: Python / MATLAB
*   **Simulação**: Ferramentas de simulação Verilog (e.g., ModelSim, Vivado Simulator)

## 6. Validação do Desempenho

A validação da arquitetura será realizada por simulação digital completa. O desempenho do sistema será avaliado através da análise da redução da distorção espectral e da melhoria da linearidade do sinal após a aplicação do DPD. Métricas como a Razão de Potência de Canal Adjacente (ACPR) e o Erro de Magnitude Vetorial (EVM) serão utilizadas para quantificar a eficácia da linearização.

## 7. Suporte e Contribuições

Este projeto está aberto a discussões e sugestões. Para suporte, análise, refinamento da arquitetura, geração de módulos em Verilog, estratégias de modelagem do amplificador, integração hardware-software e métodos de validação do desempenho do sistema, por favor, entre em contato com os desenvolvedores ou abra uma *issue* no repositório.

## 8. Licença

[Inserir informações de licença, se aplicável, e.g., MIT License]
