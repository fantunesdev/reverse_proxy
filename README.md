# Proxy da rede local

O MyFinance atende em `https://myfinance.com` e `https://192.168.100.10`.
O serviço `myprod.com` continua em HTTP, na porta 82 do servidor.
O HTTPS termina neste Nginx; ele acessa `nginx-myfin:80` pela rede Docker
externa `myfinance-proxy`. Inicie o MyFinance antes deste proxy, inclusive após
reiniciar a VM: o Nginx precisa resolver o nome do serviço para iniciar.

## Certificado local (no Pop!_OS)

Requer OpenSSL. Na pasta deste repositório, execute:

```bash
sh scripts/issue-local-cert.sh
```

A pasta `.local-pki/`, ignorada pelo Git, contém a autoridade local e o certificado.
Faça backup protegido de `root-ca.key` e `root-ca.crt`: renovações reutilizam essa
CA. Não copie a chave da CA para o servidor nem para celulares.
O certificado inclui o nome DNS e o IP como Subject Alternative Names.

Instale a autoridade no Pop!_OS:

```bash
sudo cp .local-pki/root-ca.crt /usr/local/share/ca-certificates/myfinance-local.crt
sudo update-ca-certificates
```

Reinicie o navegador. Se o Firefox não usar as autoridades do sistema, importe
`root-ca.crt` em Configurações → Privacidade e segurança → Certificados →
Ver certificados → Autoridades, permitindo identificar sites.
Mantenha `192.168.100.10 myfinance.com` no `/etc/hosts` do PC.

Nos Androids, copie somente `root-ca.crt` por um meio confiável. Em Configurações,
procure Instalar certificado → Certificado de CA (geralmente em Segurança →
Criptografia e credenciais). Os nomes variam por fabricante. Confirme a impressão
digital antes da instalação:

```bash
openssl x509 -in .local-pki/root-ca.crt -noout -fingerprint -sha256
```

Acesse pelo Chrome atualizado em `https://192.168.100.10`. A instalação da CA
é necessária em cada dispositivo. Outros navegadores/apps podem ter sua própria
política de confiança. O Android pode exibir uma notificação de CA instalada;
isso é diferente de um aviso de certificado inválido na página.

## Instalação na VM Alpine

Atualize os três repositórios (`myfinance`, Docker do MyFinance e este proxy).
Adapte o usuário SSH se necessário. No PC:

```bash
ssh fernando@192.168.100.10 'mkdir -p /docker/reverse_proxy/certs && chmod 700 /docker/reverse_proxy/certs'
scp .local-pki/myfinance.crt .local-pki/myfinance.key fernando@192.168.100.10:/docker/reverse_proxy/certs/
```

Na VM, preserve as variáveis existentes no `/docker/myfinance/.env` e acrescente:

```dotenv
MYFIN_TRUST_HTTPS_PROXY=true
MYFIN_SESSION_COOKIE_SECURE=true
MYFIN_CSRF_COOKIE_SECURE=true
```

Hosts, CORS e CSRF já devem permitir os dois endereços. O debug não foi alterado.
Não ative essas opções no Compose de desenvolvimento, que continua usando HTTP.
A pasta `/docker/myfinance` da VM corresponde ao repositório Docker do MyFinance;
elas não representam necessariamente o mesmo nome de pasta usado no PC.

Crie a rede uma única vez e suba os serviços nesta ordem, em uma janela de manutenção:

```bash
chmod 600 /docker/reverse_proxy/certs/myfinance.key
docker network inspect myfinance-proxy >/dev/null 2>&1 || docker network create myfinance-proxy
cd /docker/myfinance
docker compose config --quiet
docker compose up --build -d app-myfin nginx-myfin
cd /docker/reverse_proxy
docker compose config --quiet
docker compose run --rm --no-deps nginx-proxy nginx -t
docker compose up -d
```

Se a VM usa `docker-compose` em vez de `docker compose`, substitua o comando.
Permita TCP 80 e 443 da rede local no firewall da VM, caso haja filtragem.
A porta 81 passa a escutar apenas em `127.0.0.1`; o proxy usa a rede Docker.
O mapeamento antigo `8111:8111` foi removido, pois Daphne atende em 8000.
Não publique a porta 8000 do Django: o cabeçalho de protocolo só deve vir dos
proxies controlados. Configure a inicialização OpenRC para iniciar a stack
MyFinance antes de `reverse_proxy`.

## Validação e renovação

No PC, sem usar `-k`:

```bash
curl --cacert .local-pki/root-ca.crt --resolve myfinance.com:443:192.168.100.10 -I https://myfinance.com/
curl --cacert .local-pki/root-ca.crt -I https://192.168.100.10/
curl -I http://192.168.100.10/
```

As duas primeiras chamadas devem aceitar o certificado; a terceira deve retornar
308 para o mesmo endereço em HTTPS. Teste login, envio de formulários, uploads,
estáticos e WebSocket (`wss://`, resposta 101 nas ferramentas do navegador).
Confirme os cookies `sessionid` e `csrftoken` com atributo Secure.
Teste `http://myprod.com` para confirmar o serviço existente.

Renove antes de 365 dias: execute o mesmo script no PC usando a mesma pasta CA,
transfira novamente os dois arquivos do servidor e execute na VM:

```bash
cd /docker/reverse_proxy
docker compose exec nginx-proxy nginx -t
docker compose exec nginx-proxy nginx -s reload
```

Os dispositivos continuam confiando na mesma CA; não é preciso reinstalá-la.
A CA dura dez anos e deve ser substituída e reinstalada antes de expirar.

Para reverter, restaure as configurações anteriores dos dois Nginx e do Compose,
defina as três novas variáveis como `false` e recrie os serviços. Apague os cookies
da aplicação no navegador ao voltar a HTTP.

Referências: [Django e proxy HTTPS](https://docs.djangoproject.com/en/4.2/ref/settings/#secure-proxy-ssl-header),
[Nginx HTTPS](https://nginx.org/en/docs/http/configuring_https_servers.html),
[certificados no Android](https://support.google.com/pixelphone/answer/2844832?hl=pt-BR).
