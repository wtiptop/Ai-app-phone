enum AgentDomain {
  personalAssistant,
  programming,
  research,
  finance,
  technology,
  gamesAndRpg,
  communication,
}

class DomainTeam {
  const DomainTeam(this.domain, this.manager, this.workers, this.controller);
  final AgentDomain domain;
  final String manager;
  final List<String> workers;
  final String controller;
}

/// Role definitions only. No hidden background processes or paid invocations.
const domainTeams = <DomainTeam>[
  DomainTeam(
      AgentDomain.personalAssistant,
      'Koordynator asystenta',
      [
        'Planista',
        'Redaktor dokumentów',
        'Tłumacz PL–DE',
      ],
      'Kontroler asystenta'),
  DomainTeam(
      AgentDomain.programming,
      'Architekt IT',
      [
        'Programista',
        'Tester',
        'Specjalista bezpieczeństwa',
      ],
      'Niezależny recenzent kodu'),
  DomainTeam(
      AgentDomain.research,
      'Koordynator badań',
      [
        'Badacz źródeł',
        'Weryfikator cytowań',
      ],
      'Kontroler źródeł'),
  DomainTeam(
      AgentDomain.finance,
      'Koordynator gospodarki i GPW',
      [
        'Analityk raportów',
        'Weryfikator tickerów i nazw',
      ],
      'Kontroler finansowy'),
  DomainTeam(
      AgentDomain.technology,
      'Koordynator technologii i AI',
      [
        'Badacz technologii',
        'Redaktor przeglądu',
      ],
      'Kontroler technologii'),
  DomainTeam(
      AgentDomain.gamesAndRpg,
      'Koordynator gier i RPG',
      [
        'Badacz gier',
        'Koordynator kampanii',
      ],
      'Kontroler RPG'),
  DomainTeam(
      AgentDomain.communication,
      'Koordynator komunikacji',
      [
        'Redaktor wiadomości',
        'Tłumacz PL–DE',
      ],
      'Kontroler komunikacji'),
];
