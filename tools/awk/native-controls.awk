# Native records, as documented by each generator's own input parser. Read the
# entire file before changing it; the caller replaces it only after success.
function die(message) {print eng ": " message > "/dev/stderr"; bad=1; exit 61}
function trim(s) {gsub(/^[ \t]+|[ \t]+$/, "", s); return s}
function num(s) {gsub(/[dD]/,"e",s); return s+0}
function lnum(s) {return s=="s"?0:s=="p"?1:s=="d"?2:s=="f"?3:s+0}
function lname(l) {return substr("spdf",l+1,1)}
function field(r,c, a) {split(X[P[r]],a);return a[c]}
function set(r,c,v, a,n,i,s) {
    if(!(r in P))die("incomplete native record " r)
    n=split(X[P[r]],a); a[c]=v; if(c>n)n=c
    s=a[1];for(i=2;i<=n;i++)s=s " " a[i]; X[P[r]]=s
}
function opt(k) {used[k]=1;return O[k]}
function kw(k,v,equals, i,a,left,n,found) {
    for(i=1;i<=N;i++) {
        if(equals){n=index(X[i],"=");if(!n)continue;left=trim(substr(X[i],1,n-1))}
        else {split(X[i],a);left=a[1]}
        if(tolower(left)==tolower(k)){if(found++)die("duplicate native keyword " k);X[i]=k (equals?" = ":" ") v}
    }
    if(!found)X[++N]=k (equals?" = ":" ") v
}
BEGIN {
    n=split(opts,a," ");for(i=1;i<=n;i++){j=index(a[i],"=");O[substr(a[i],1,j-1)]=substr(a[i],j+1)}
    n=split(radii,a," ");for(i=1;i<=n;i++){split(a[i],b,":");R[lnum(b[1])]=num(b[2])}
    sf=(scale==""?1:num(scale))
}
{ X[++N]=$0; if($0 !~ /^[ \t]*(#|!|$)/)P[++NRD]=N }
END {
    if(bad)exit 61
    if(eng=="oncvpsp" || eng=="oncv-scale") {
        nc=num(field(1,3))+num(field(1,4)); lm=field(nc+2,1)+0
        lr=nc+lm+4; pr=lr+1
        if(nc<1 || lm<0 || lm>3 || NRD<lr+lm+5)die("incomplete ONCVPSP positional input")
        if(eng=="oncv-scale") {
            top=num(field(lr+lm+4,1))
            if(top<=0)die("invalid ONCVPSP output grid rlmax")
            for(l=0;l<=lm;l++) {
                r=nc+3+l;v=num(field(r,2))*sf
                if(v<=0 || v>=top)die("scaled radius reaches ONCVPSP output grid rlmax")
                set(r,2,sprintf("%.12g",v))
            }
            v=num(field(lr,3))*sf
            if(v<=0 || v>=top)die("scaled local radius reaches ONCVPSP output grid rlmax")
            set(lr,3,sprintf("%.12g",v))
        }
        for(l=0;l<=lm;l++) {
            r=nc+3+l; s=lname(l)
            if("qcut." s in O)set(r,6,opt("qcut." s))
            if("ncon." s in O)set(r,4,opt("ncon." s))
            if("nbas." s in O)set(r,5,opt("nbas." s))
            if("nproj." s in O)set(pr+l,2,opt("nproj." s))
            delta=num(field(r,5))-num(field(r,4))
            if(delta<(num(field(pr+l,2))==2?3:2) || delta>5)die("nbas must be ncon+3..ncon+5 for two projectors, ncon+2..ncon+5 for one")
            if("debl." s in O){if(field(pr+l,2)<2)die("projector energy separation needs two projectors");set(pr+l,3,opt("debl." s))}
        }
        if("dvloc0" in O){if(field(lr,1)!=4)die("dvloc0 requires lloc=4");set(lr,4,opt("dvloc0"))}
    } else if(eng=="uspp-ae") {
        th=num(substr(X[P[3]],1,10)); to=num(substr(X[P[3]],11,10)); da=num(substr(X[P[3]],21,10))
        if("thresh" in O)th=num(opt("thresh"));if("tol" in O)to=num(opt("tol"));if("damp" in O)da=num(opt("damp"))
        X[P[3]]=sprintf("%10.3E%10.3E%10.5f",th,to,da) substr(X[P[3]],31)
        for(key in O)used[key]=1
    } else if(eng=="uspp") {
        # rwsubs.f: (2i5,2f10.5), optional (5f10.5), (i5,f10.5), (3f10.5).
        nang=field(5,3)+0
        inner=num(substr(X[P[7]],11,10)); core=num(substr(X[P[7]],21,10))
        ni=int((2*nang-2)/5)+1
        localrow=(inner==0?8+ni:8); rcrow=localrow+1
        if(nang<1 || nang>5 || field(1,2)!=2)die("expected a USPP generation input")
        newinner=("rinner" in O?num(opt("rinner")):inner*sf)
        newcore=(rcore!=""?num(rcore):core*sf)
        ic=num(substr(X[P[7]],6,5)); if(nlcc!="")ic=(nlcc=="on")
        if(rcore!="" && nlcc=="")ic=1
        if(ic && newcore<=0)die("NLCC needs a positive --rcore (rpcor)")
        if(newinner<0 || newinner>=10000 || newcore<0 || newcore>=10000)die("USPP radius exceeds fixed-field range")
        if((inner!=0 || "rinner" in O) && newinner<0.00001)die("rinner is below USPP fixed-field precision")
        if(ic && newcore<0.00001)die("core radius is below USPP fixed-field precision")
        # Switching an L-dependent list to a scalar would change the record
        # count. Keep the existing layout and fill that list instead.
        scalar=(inner==0?0:newinner)
        X[P[7]]=sprintf("%5d%5d%10.5f%10.5f",num(substr(X[P[7]],1,5)),ic,scalar,newcore) substr(X[P[7]],31)
        if(inner==0) {
            for(j=0;j<ni;j++) {
                line="";for(i=1;i<=5 && j*5+i<=2*nang-1;i++){v=("rinner" in O?newinner:num(substr(X[P[8+j]],(i-1)*10+1,10))*sf);if(v<0.00001 || v>=10000)die("angular rinner exceeds USPP fixed-field precision");line=line sprintf("%10.5f",v)}
                X[P[8+j]]=line
            }
        }
        localrc=(rcloc!=""?num(rcloc):num(field(localrow,2))*sf)
        if(localrc<0.00001 || localrc>=10000)die("USPP local radius exceeds fixed-field range")
        X[P[localrow]]=sprintf("%5d%10.5f",field(localrow,1),localrc) substr(X[P[localrow]],16)
        for(j=0;j<int((nang-1)/3)+1;j++) {
            line="";for(i=0;i<3 && j*3+i<nang;i++){l=j*3+i;v=(l in R?R[l]:num(substr(X[P[rcrow+j]],i*10+1,10))*sf);if(v<0.00001 || v>=10000)die("radius exceeds fixed-field precision");line=line sprintf("%10.5f",v);seen[l]=1}
            X[P[rcrow+j]]=line substr(X[P[rcrow+j]],i*10+1)
        }
        th=num(substr(X[P[3]],1,10)); to=num(substr(X[P[3]],11,10)); da=num(substr(X[P[3]],21,10))
        if("thresh" in O)th=num(opt("thresh"));if("tol" in O)to=num(opt("tol"));if("damp" in O)da=num(opt("damp"))
        if("damp" in O && da<0.00001)die("SCF damping is below USPP fixed-field precision")
        X[P[3]]=sprintf("%10.3E%10.3E%10.5f",th,to,da) substr(X[P[3]],31)
    } else if(eng=="fhi98pp") {
        last=field(1,2)+field(1,3)+2; lm=field(last,1)+0
        if(lm<0 || lm>4 || NRD<last)die("incomplete fhi98PP atom and channel table")
        if(rcore!="")set(1,5,rcore)
        if(nlcc=="off")set(1,5,0)
        if(nlcc=="on" && num(field(1,5))<=0)die("NLCC needs an explicit positive --rcore")
        scheme="";if("scheme" in O){scheme=(opt("scheme")=="tm"?"t":"h");set(last,2,scheme)}
        for(r=last+1;r<=NRD;r++) {
            l=field(r,1)+0
            if(l in R){set(r,2,R[l]);seen[l]=1}
            if(scheme!="")set(r,4,scheme)
        }
        for(l in R)if(!(l in seen)){if(l>lm)die("channel exceeds lmax");X[++N]=l " " R[l] " 0.0 " (scheme!=""?scheme:field(last,2));seen[l]=1}
    } else if(eng=="opium") {
        atom=0;pseudo=0;for(r=1;r<=NRD;r++){if(tolower(field(r,1))=="[atom]")atom=r;if(tolower(field(r,1))=="[pseudo]")pseudo=r}
        if(!pseudo || !atom)die("missing Atom/Pseudo section")
        n=num(field(pseudo+1,1)); total=num(field(atom+2,1))
        for(i=1;i<=n;i++) {
            shell=field(atom+2+total-n+i,1)
            if(shell!~/^[1-9][0-4][0-2]$/)die("unsupported OPIUM orbital label; edit native radii directly")
            l=substr(shell,2,1)+0
            if(l in R){set(pseudo+1,i+1,R[l]);seen[l]=1}
        }
        if("method" in O)set(pseudo+2,1,opt("method"))
    } else if(eng=="ape") {
        inside=0
        for(i=1;i<=N;i++) {
            if(X[i]~/^[ \t]*%PPComponents/){inside=1;continue}
            if(inside && X[i]~/^[ \t]*%/){inside=0;continue}
            if(inside && index(X[i],"|")) {
                k=split(X[i],a,"|");l=num(a[2]);if(l in R){a[3]=" " R[l] " ";seen[l]=1}
                if("scheme" in O){if(k!=4)die("scheme change needs a single-projector four-column component");a[4]=" " opt("scheme")}
                line=a[1];for(j=2;j<=k;j++)line=line "|" a[j];X[i]=line
            }
        }
        if(lloc!="")kw("LLocal",lloc,1)
        if(nlcc!="")kw("CoreCorrection",(nlcc=="on"?2:0),1)
        if(rcore!=""){if(nlcc=="off")die("rcore with NLCC off");kw("CoreCorrection",2,1);kw("CoreCorrectionCutoff",rcore,1)}
        for(key in O)if(key!="scheme")kw(key,opt(key),1)
    } else if(eng=="adpack") {
        inside=0;have=0
        for(i=1;i<=N;i++) {
            split(X[i],a)
            if(a[1]=="<pseudo.NandL"){inside=1;continue}
            if(a[1]=="pseudo.NandL>"){inside=0;continue}
            if(inside && a[1]~/^[0-9]+$/){l=a[3]+0;v=(l in R?R[l]:num(a[4])*sf);X[i]=a[1] " " a[2] " " a[3] " " v " " a[5];seen[l]=1;have++}
        }
        if(!have)die("missing pseudo.NandL channels")
        if(rcloc!="")kw("local.cutoff",rcloc,0)
        else if(scale!="") {
            for(i=1;i<=N;i++){split(X[i],a);if(a[1]=="local.cutoff")kw("local.cutoff",num(a[2])*sf,0)}
        }
        if(nlcc!="")kw("charge.pcc.calc",nlcc,0)
        if("pcc.ratio" in O || "pcc.ratio.origin" in O) {
            enabled=0;for(i=1;i<=N;i++){split(X[i],a);if(a[1]=="charge.pcc.calc" && tolower(a[2])=="on")enabled=1}
            if(!enabled)die("partial-core ratios need --nlcc on or an enabled native charge.pcc.calc")
        }
        if(beta!="")kw("scf.Init.Mixing.Weight",beta,0)
        if(tr2!="")kw("scf.criterion",tr2,0)
        for(key in O)kw(key,opt(key),0)
    } else if(eng=="atompaw") {
        split(X[P[3]],maxn);mark=0;for(l=0;l<6;l++)if(maxn[l+1]>l)mark+=maxn[l+1]-l
        r=4;while(r<=NRD && !(field(r,1)==0 && field(r,2)==0 && field(r,3)==0)){vcount[field(r,2)+0]++;r++}
        r+=mark+1;lm=field(r,1)+0;paw=r+1
        if(lm<0 || lm>4 || field(paw,1)+0<=0)die("unsupported AtomPAW orbital/marker layout; edit native input directly")
        split(X[P[paw]],a);line="";for(i=1;i<=length(a);i++)line=line (i==1?"":" ") num(a[i])*sf
        X[P[paw]]=line;radius=num(field(paw,1));r=paw+1
        for(l=0;l<=lm;l++) {
            count[l]=vcount[l];while(tolower(field(r,1))=="y") {count[l]++;r++;if("paw.projector_energy" in O)set(r,1,opt("paw.projector_energy"));r++}
            if(tolower(field(r,1))!="n")die("unsupported AtomPAW projector layout");r++
        }
        if(toupper(field(r,1))!="VANDERBILT")die("typed radii currently require AtomPAW VANDERBILT layout; edit the native input for other methods")
        if("paw.shape" in O)set(r,2,opt("paw.shape"))
        if("paw.local_channel" in O)set(r+1,1,opt("paw.local_channel"))
        r+=2
        for(l=0;l<=lm;l++)for(i=0;i<count[l];i++) {
            v=(l in R?R[l]:num(field(r,1))*sf)
            if(v<=0 || v>radius+1e-10)die("projector radius must be positive and <= PAW radius; increase --rcut-scale first")
            set(r,1,v);seen[l]=1;r++
        }
    } else if(eng=="gth") {
        if(kind=="atom.dat") {
            if("atom.rmax" in O)set(4,1,opt("atom.rmax"))
            if("atom.rcov" in O)set(5,1,opt("atom.rcov"))
            if("atom.rprb" in O)set(5,2,opt("atom.rprb"))
        } else if(kind=="psp.par") {
            lm=field(6,1)+0
            if("atom.rcov" in O)set(2,1,opt("atom.rcov"))
            if("atom.rprb" in O)set(2,2,opt("atom.rprb"))
            set(5,3,(rcloc!=""?num(rcloc):num(field(5,3))*sf))
            l=0;for(r=7;r<=NRD;r++)if(index(X[P[r]],"so=+0.5")){if(l<=lm){set(r,1,(l in R?R[l]:num(field(r,1))*sf));seen[l]=1}l++}
            for(key in O)if(key~/^atom\.|^fit\./)used[key]=1
        } else if(kind=="FITPAR") {
            lm=field(3,1)+0
            if(rcloc!="" || scale!="")set(2,1,"f")
            if("fit.rloc_free" in O)set(2,1,(opt("fit.rloc_free")==1?"t":"f"))
            for(l=0;l<=lm;l++) {
                if(l in R || scale!="")set(l+4,1,"f")
                if("fit.radius_free" in O)set(l+4,1,(opt("fit.radius_free")==1?"t":"f"))
                seen[l]=1
            }
        } else if(kind=="weights.par") {
            for(r=1;r<=NRD;r++)if(field(r,1)~/^[0-9]+$/ && field(r,2)~/^[0-9]+$/) {
                if("fit.eigenvalue_weight" in O)set(r,4,num(field(r,4))*num(opt("fit.eigenvalue_weight")))
                if("fit.charge_weight" in O)set(r,5,num(field(r,5))*num(opt("fit.charge_weight")))
            }
        }
        # Options live in separate native files; their owning adapter validates
        # them, and the complete four-file set is committed together.
        for(key in O)used[key]=1
        if(kind!="psp.par" && kind!="FITPAR")for(l in R)seen[l]=1
    }
    if(eng!="oncvpsp" && eng!="oncv-scale")for(l in R)if(!(l in seen))die("requested radius channel " l " is absent")
    for(key in O)if(!(key in used))die("native control " key " has no applicable record")
    for(i=1;i<=N;i++)print X[i]
}
