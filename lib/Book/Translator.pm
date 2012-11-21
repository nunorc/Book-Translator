package Book::Translator;
use Dancer ':syntax';
use Dancer::Plugin::Database;
use Digest::MD5 'md5_hex';

use utf8;
our $VERSION = '0.1';

get '/translate/:id' => sub {
    redirect '/' unless session('user');
    my $id = param('id');
    redirect '/' unless $id =~ /^\d+$/;
	
    # 1. meter na BD o email do utilizador no registo da tabela doc,
    #    para marcar como "em processamento"

    database->quick_update( 'doc', { id => param('id') }, { status => 'reserved',
                                                            user => session('user') });
    # 2. mostrar text area nao editavel com original
    # 3. mostrar text area editavel com o original para traducao
    my ($r) = database->quick_select('doc' => { id => $id });
    my $left = $r->{text};
    $left = __escape($left);
    my $terms = __terms();
    $left =~ s/(\w+)/__find_terms($1, $terms)/eg;

    my $right;
    if (exists($r->{trans}) and length($r->{trans})) {
        $right = $r->{trans};
    }
    else {
        $right = $r->{text};
    }

    template 'translate' => { id => $id,
                              before => context_before($id),
                              after => context_after($id),
                              section => $r->{section},
                              left => $left,
                              right => __escape_ampersands($right),
                            };
};

get '/faq' => sub {
    template 'faq' => { terms => __terms() }
};

get '/view/:id' => sub {
    redirect '/' unless session('user');
    my $id = param('id');
    redirect '/' unless $id =~ /^\d+$/;

    my $r = database->quick_select( doc => { id => $id } );
    template 'view' => { id => $id,
                         section => $r->{section},
                         before => context_before($id),
                         after => context_after($id),
                         left => $r->{text},
                         right => $r->{trans}
                       };
};

post '/approve/:id' => sub {
    redirect '/' unless session('user');
    redirect '/' unless session('admin');
    redirect '/' unless param('id') =~ /^\d+$/;

    if (param('action') eq "Devolver") {
        database->quick_update('doc'=>{id=>param('id')}=>{status=>'reserved'});
        forward '/';
    } elsif (param('action') eq "Aprovar") {
        database->quick_update('doc' => { id => param('id') },
                               { status => "done", trans => param("right") });
        forward '/';
    } else {
        param("action");
    }
};

get '/return/:id' => sub {
    redirect '/' unless session('user');
    redirect '/' unless session('admin');
    redirect '/' unless param('id') =~ /^\d+$/;

    database->quick_update('doc'=>{id=>param('id')}=>{status=>'free'});
    forward '/';
};

get '/bless/:id' => sub {
    redirect '/' unless session('user');
    redirect '/' unless session('admin');
    redirect '/' unless param('id') =~ /^\d+$/;

    my $id = param('id');
    my ($r) = database->quick_select('doc' => { id => $id });
    template 'bless' => { id => $id,
                          before => context_before($id),
                          after => context_after($id),
                          section => $r->{section},
                          left => __escape_ampersands($r->{text}),
                          right => __escape_ampersands($r->{trans})
                        };
};

post '/save/:id' => sub {
    redirect '/' unless session('user');
    redirect '/' unless param('id') =~ /^\d+$/;

    if (param("action") eq "Guardar") {
        database->quick_update('doc' => { id => param('id') },
                               { trans => param("right") });
        forward '/';
    }
    elsif (param("action") eq "Terminar") {
        my $r = database->quick_select(doc=>{id=>param('id')});
        database->quick_update('doc' => { id => param('id') },
                               { trans => param("right") });
        my $diffs;
        if ($diffs = __compare_tags($r->{text}, param("right"))) {
            template 'register' => { msg => "Tradução guardada mas não terminada. Verifique as etiquetas XML.<br/>".__escape($diffs) };
        } else {
            database->quick_update(doc=>{id=>param('id')}=>{status=>'translated'});
            forward '/';
        }
    }
    elsif (param("action") eq "!!! Forçar !!!" && session('admin')) {
        database->quick_update('doc' => { id => param('id') },
                               { trans => param("right"), status=>'translated'});
        forward '/';
    }
    elsif (param("action") eq "Devolver") {
        database->quick_update( 'doc', { id => param('id') }, { status => 'free',
                                                                user => "" });
        forward '/';
    }
    elsif (param("action") eq "Limpar") {
        redirect request->uri_base . "/translate/".param('id');
    }
    else {
        param("action");
    }
};

get '/logout' => sub {
    session->destroy;
    # template register => { msg => 'Sessão terminada' };
    forward '/';
};

any ['get','post'] => '/' => sub {
    if (session('user')) {
        my $where = {};
        if (param('status')) {
            $where->{status} = param('status');
        }
        if (param('mine')) {
            $where->{user} = session('user');
        }
        my @rows = database->quick_select('doc', $where);
        template 'main' => { nome => session('name'),
                             stats => __stats(),
                             chunks => \@rows };
    } else {
        template 'index';
    }
};

post '/enter' => sub {
    if (!param("email") || !param("pass")) {
        template register => { msg => 'Permissão negada' }
    }
    else {
        my ($r) = database->quick_select('user' => { email => param("email") });
        if ($r && $r->{passwd} eq md5_hex(param("pass"))) {
            session user => param("email");
            session name => $r->{nome};
            session admin => $r->{admin};
            #template register => { msg => 'Bem vindo' }
            forward '/';
        } else {
            template register => { msg => 'Permissão negada' }
        }
    }
};

post '/register' => sub {
    return; # XXX
    if (!param("name")) {
        template 'register' => {msg => "Nome obrigatório"};
    }
    elsif (!param("email")) {
        template 'register' => {msg => 'Email obrigatório'};
    }
    elsif (!param("pass1")) {
        template 'register' => {msg => 'Palavra chave obrigatória'};
    }
    elsif (param("pass1") ne param("pass2")) {
        template 'register' => {msg => 'Palavras chave diferem'};
    }
    else {
        database->quick_insert('user' => { nome => param("name"),
                                           email => param("email"),
                                           admin => 0,
                                           passwd => md5_hex(param("pass1")) });
        template 'register' => {msg => 'Registo realizado com sucesso'};
    }
};

get '/user/:name' => sub {
    my $name = param('name');

    my ($r) = database->quick_select('user' => { nome => $name });

    template 'user' => { user => $r };
};

post '/user/:name' => sub {
    my $name = param('name');
    my $pass1 = param('pass1');
    my $pass2 = param('pass2');
    my $pass3 = param('pass3');

    my ($r) = database->quick_select('user' => { nome => $name });
    if ($r->{email} eq session('user')) {
        if ( (md5_hex($pass1) eq $r->{passwd}) and ($pass2 eq $pass3) ) {
            my $md5 = md5_hex($pass2);
            database->quick_update('user', {email=>session('user')}, {passwd=>$md5});

            return template register => { msg => 'Palavra chave alterada' };
        }
    }

    template 'user' => { user => $r };
};

sub __compare_tags {
	my ($s1, $s2) = @_;

        $s1 =~ s/[\n\r]//g;
        $s2 =~ s/[\n\r]//g;

	my @left;
	push @left, $1 while ($s1 =~ m/<([^>]+)>/g);
	my @right;
	push @right, $1 while ($s2 =~ m/<([^>]+)>/g);

        while (@left || @right) {
            my $l = shift @left  || "";
            my $r = shift @right || "";
            return "Diferenças começam com <$l> vs <$r>" if $l ne $r;
        }
        return undef;
	# return (@left ~~ @right);
}

sub __stats {
    my $stats;
    my $sth = database->prepare("SELECT status, COUNT(*) FROM doc GROUP BY status;");
    $sth->execute;
    my @r;
    my $tot = 0;
    while (@r = $sth->fetchrow_array) {
        $stats->{$r[0]} = $r[1];
        $tot+=$r[1];
    }
    for (keys %$stats) {
        $stats->{$_} = 100*$stats->{$_}/$tot;
    }
    return $stats;
}

sub context_before {
    my $id = shift;

    my $sth = database->prepare("SELECT text, trans FROM doc WHERE id < ? ORDER BY id DESC LIMIT 2 ");
    $sth->execute($id);
    my @row;
    my @textA;
    my @textB;
    while (@row = $sth->fetchrow_array) {
        unshift @textA, $row[0];
        unshift @textB, $row[1] || "";
    }
    return "<td style='font-size: 8pt; background-color: #ccc'>".__escape(join("\n", @textA))."</td><td style='font-size: 8pt; background-color: #ccc'>".__escape(join("\n", @textB))."</td>"
}

sub context_after {
    my $id = shift;
    my $sth = database->prepare("SELECT text, trans FROM doc WHERE id > ? ORDER BY id ASC LIMIT 2 ");
    $sth->execute($id);
    my @row;
    my @textB = ();
    my @textA = ();
    while (@row = $sth->fetchrow_array) {
        push @textA, $row[0];
        push @textB, $row[1] || "";
    }
    return "<td style='font-size: 8pt; background-color: #ccc'>".__escape(join("\n", @textA))."</td><td style='font-size: 8pt; background-color: #ccc'>".__escape(join("\n", @textB))."</td>"
}

sub __escape {
    my $x = shift;
    for ($x) {
        s/&/&amp;/g;
        s/</&lt;/g;
        s/>/&gt;/g;
    }
    return $x;
}


sub __escape_ampersands {
    my $x = shift;
    $x =~ s/&/&amp;/g;
    return $x;
}

sub __find_terms {
    my ($term, $terms) = @_;

    if (exists $terms->{$term}) {
        return "<a class='more' href='javascript: void(0);'>$term<span>Sugestões de tradução para <strong>$term</strong>: $terms->{$term}</span></a>";
    }
    else { return $term; }
}

sub __terms {
    my @rows = database->quick_select('terms', {});
    my $x = {};
    $x->{$_->{term}} = $_->{translation} for (@rows);
    return $x;
}

true;
