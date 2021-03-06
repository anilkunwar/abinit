!{\src2tex{textfont=tt}}
!!****f* ABINIT/pred_moldyn
!! NAME
!! pred_moldyn
!!
!! FUNCTION
!! Ionmov predictor (1) Molecular dynamics
!!
!! Molecular dynamics, with or without viscous damping
!! This function should be after the call to scfcv
!! Updates positions, velocities and forces
!!
!! COPYRIGHT
!! Copyright (C) 1998-2012 ABINIT group (DCA, XG, GMR, SE)
!! This file is distributed under the terms of the
!! GNU General Public License, see ~abinit/COPYING
!! or http://www.gnu.org/copyleft/gpl.txt .
!!
!! INPUTS
!! ab_mover<type ab_movetype>=Subset of dtset only related with
!!          |                 movement of ions and acell, contains:
!!          | dtion:  Time step
!!          ! natom:  Number of atoms
!!          | vis:    viscosity
!!          | iatfix: Index of atoms and directions fixed
!!          | amass:  Mass of ions
!! icycle: Index of the internal cycle inside a time step (itime)
!! itime: Index of time iteration
!! zDEBUG : if true print some debugging information
!!
!! OUTPUT
!!
!! SIDE EFFECTS
!! hist<type ab_movehistory>=Historical record of positions, forces
!!      |                    acell, stresses, and energies,
!!      |                    contains:
!!      | mxhist:  Maximun number of records
!!      | histA:   Historical record of acell(A) and rprimd(R)
!!      | histE:   Historical record of energy(E)
!!      | histEk:  Historical record of Ionic kinetic energy(Ek)
!!      | histT:   Historical record of time(T) (For MD or iteration for GO)
!!      | histR:   Historical record of rprimd(R)
!!      | histS:   Historical record of strten(S)
!!      | histV:   Historical record of velocity(V)
!!      | histXF:  Historical record of positions(X) and forces(F)
!!
!! ncycle: Number of cycles of a particular time step
!!
!! NOTES
!! * This routine is a predictor, it only produces new positions
!!   to be computed in the next iteration, this routine should
!!   produce not output at all
!! * ncycle changes from 4 for the first iteration (itime==1)
!!   to 1 for (itime>1)
!! * The arrays vec_tmp1 and vec_tmp2 are triky, they are use with
!!   different meanings, during the initialization they contains
!!   working positions and velocities that acumulated produce the
!!   first positions of itime=1, for itime>1 they will contain
!!   positions in 2 previous steps, those values are different
!!   from the values store in the history, thats the reason why
!!   we cannot simply use histXF to obtain those positions.
!!
!! PARENTS
!!      mover
!!
!! CHILDREN
!!      hist2var,var2hist,xredxcart
!!
!! SOURCE

#if defined HAVE_CONFIG_H
#include "config.h"
#endif

#include "abi_common.h"

subroutine pred_moldyn(ab_mover,hist,icycle,itime,ncycle,ntime,zDEBUG,iexit)

 use m_profiling

! define dp,sixth,third,etc...
use defs_basis
! type(ab_movetype), type(ab_movehistory)
use defs_mover

!This section has been created automatically by the script Abilint (TD).
!Do not modify the following lines by hand.
#undef ABI_FUNC
#define ABI_FUNC 'pred_moldyn'
 use interfaces_42_geometry
 use interfaces_45_geomoptim, except_this_one => pred_moldyn
!End of the abilint section

implicit none

!Arguments ------------------------------------
!scalars
type(ab_movetype),intent(in)       :: ab_mover
type(ab_movehistory),intent(inout) :: hist
integer,intent(in)    :: icycle
integer,intent(inout) :: ncycle
integer,intent(in)    :: itime
integer,intent(in)    :: ntime
integer,intent(in)    :: iexit
logical,intent(in)    :: zDEBUG

!Local variables-------------------------------
!scalars
integer  :: kk,jj
real(dp) :: aa,alfa,bb,cc,x0,xm,em,vis,dx,dv
real(dp) :: fcart,fprev,fprev2
real(dp) :: xc
real(dp) :: vel,vnow,xnow,vprev
real(dp),save :: hh,time
!arrays
real(dp) :: acell(3)
real(dp) :: rprimd(3,3),rprim(3,3)
real(dp) :: xred(3,ab_mover%natom),xcart(3,ab_mover%natom)
real(dp),save,allocatable :: vec_tmp1(:,:)
real(dp),save,allocatable :: vec_tmp2(:,:)

!***************************************************************************
!Beginning of executable session
!***************************************************************************

 if(iexit/=0)then
   if(allocated(vec_tmp1))  then
     ABI_DEALLOCATE(vec_tmp1)
   end if
   if(allocated(vec_tmp2))  then
     ABI_DEALLOCATE(vec_tmp2)
   end if
   return
 end if

 vis= ab_mover%vis
!Just to avoid warnings of uninitialized variables
 fprev=0.0_dp
 fprev=0.0_dp
 fprev2=0.0_dp
 vnow=0.0_dp
 vprev=0.0_dp
 xnow=0.0_dp

!Those arrays contains intermediary results used with
!different meanings during the different time steps
!We need to preserv the allocation status, this is the
!reason to be 'SAVE'
 if (itime==1.and.icycle==1)then
   if(allocated(vec_tmp1))  then
     ABI_DEALLOCATE(vec_tmp1)
   end if
   if(allocated(vec_tmp2))  then
     ABI_DEALLOCATE(vec_tmp2)
   end if
   ABI_ALLOCATE(vec_tmp1,(3,ab_mover%natom))
   ABI_ALLOCATE(vec_tmp2,(3,ab_mover%natom))
 end if

!write(std_out,*) '01'
!##########################################################
!### 01. Copy from the history to the variables
 call hist2var(acell,hist,ab_mover%natom,rprim,rprimd,xcart,xred,zDEBUG)

!write(std_out,*) '01'
!##########################################################
!### 02. Get or compute de time step dtion

 if (ab_mover%dtion>0)then
   hh = ab_mover%dtion
 else
   hh=fdtion(ab_mover,hist,itime)
 end if

!write(std_out,*) '02'
!##########################################################
!### 02. For all atoms and directions
 do kk=1,ab_mover%natom
   em=ab_mover%amass(kk)
   do jj=1,3

!    write(std_out,*) '03'
!    ##########################################################
!    ### 03. Filling other values from history (forces and vel)
     fcart=hist%histXF(jj,kk,3,hist%ihist)
     xc=xcart(jj,kk)
     vel=hist%histV(jj,kk,1)

     if (itime==2)then
       fprev=hist%histXF(jj,kk,3,1)
       vprev=hist%histV(jj,kk,hist%ihist)
       vec_tmp2(jj,kk)=hist%histXF(jj,kk,1,hist%ihist)
       vec_tmp1(jj,kk)=hist%histXF(jj,kk,1,1)
     end if

!    Previous values only after first iteration
     if (itime>2.or.icycle>=2) then
       fprev=hist%histXF(jj,kk,3,hist%ihist-1)
       vprev=hist%histV(jj,kk,hist%ihist)
     end if

     if (itime==3) then
       fprev2=hist%histXF(jj,kk,3,1)
     end if

     if (itime>3.or.icycle>=3) then
       fprev2=hist%histXF(jj,kk,3,hist%ihist-2)
     end if

!    write(std_out,*) '04'
!    ##########################################################
!    ### 04. Take first the atoms that are not allowed to move along
!    ###     this direction
!    ###     Warning : implemented in cartesian coordinates
     if (ab_mover%iatfix(jj,kk)==1) then
!      Their positions will be the same as xcart
       xnow=xcart(jj,kk)
!      Their velocities are zero
       vnow=0.0_dp
     else

!      write(std_out,*) '05'
!      ##########################################################
!      ### 05. Initialization (itime==1):
!      ###     4 calls to obtain the forces are neeeded
!      ###     The variables vec_tmp2 and vec_tmp1 from previous
!      ###     calls are used in the following ones.
       if(itime==1)then
         x0=hist%histXF(jj,kk,1,1)

!        Prepare the second cycle
         if(icycle==1)then
           dx=hh*vel
           dv=hh/em*(fcart-vis*vel)
           xnow=x0+.5_dp*dx
           vnow=vel+.5_dp*dv
           vec_tmp2(jj,kk)=xc+sixth*dx
           vec_tmp1(jj,kk)=vel+sixth*dv
         else if(icycle==2)then
           dx=hh*vprev
           dv=hh/em*(fcart-vis*vprev)
           xnow=x0+.5_dp*dx
           vnow=vel+.5_dp*dv
           vec_tmp2(jj,kk)=vec_tmp2(jj,kk)+third*dx
           vec_tmp1(jj,kk)=vec_tmp1(jj,kk)+third*dv
         else if(icycle==3)then
           dx=hh*vprev
           dv=hh/em*(fcart-vis*vprev)
           xnow=x0+dx
           vnow=vel+dv
           vec_tmp2(jj,kk)=vec_tmp2(jj,kk)+third*dx
           vec_tmp1(jj,kk)=vec_tmp1(jj,kk)+third*dv
         else if(icycle==4)then
           dx=hh*vprev
           dv=hh/em*(fcart-vis*vprev)
           xnow=vec_tmp2(jj,kk)+sixth*dx
           vnow=vec_tmp1(jj,kk)+sixth*dv
         end if
       else !(itime/=1)

!        write(std_out,*) '06'
!        ##########################################################
!        ### 06. Change positions and velocities
!        ###     These changes only applies for itime>2
         if (itime>2)then
!          Uses a corrector to have better value of xnow, and
!          derive vnow. Only update atoms position and
!          velocity along its allowed directions
           aa=fprev
           bb=(fcart-fprev2)/(2._dp*hh)
           cc=(fcart+fprev2-2._dp*fprev)/(2._dp*hh*hh)
           x0=vec_tmp2(jj,kk)
           xm=vec_tmp1(jj,kk)
           if(abs(vis)<=1.d-8)then
!            NON-DAMPED DYNAMICS (Post-Code)
             xnow=2._dp*x0-xm+hh**2/em/12._dp*&
&             (fprev2+10._dp*fprev+fcart)
             vnow=(bb*hh**2)/(3._dp*em)&
&             +1.5_dp*aa*hh/em+&
&             (5._dp/12._dp)*cc*hh**3/em&
&             +x0/hh-xm/hh
           else
!            DAMPED DYNAMICS (Post-Code)
             alfa=exp(-vis*hh/em)
             xnow=((-aa*hh*vis**2+0.5_dp*bb*hh**2*vis**2&
&             -third*cc*hh**3*vis**2+em*bb*hh*vis&
&             -em*cc*hh**2*vis-2._dp*em**2*cc*hh+x0*vis**3-xm*vis**3)*alfa&
&             +aa*hh*vis**2-em*bb*hh*vis+third*cc*hh**3*vis**2&
&             +2._dp*em**2*cc*hh+0.5D0*bb*hh**2*vis**2-em*cc*hh**2*vis+x0*vis**3)&
&             /vis**3
             vnow=(em*aa*vis**2*alfa-em*aa*vis**2+bb*hh*vis**2*em*alfa&
&             -bb*hh*vis**2*em+cc*hh**2*vis**2*em*alfa-cc*hh**2*vis**2*em&
&             -em**2*bb*vis*alfa+em**2*bb*vis-2._dp*em**2*cc*hh*vis*alfa+&
&             2._dp*em**2*cc*hh*vis+2._dp*em**3*cc*alfa-2._dp*em**3*cc+&
&             vis**3*alfa**2*aa*hh-0.5_dp*vis**3*alfa**2*bb*hh**2+&
&             third*vis**3*alfa**2*cc*hh**3-vis**2*&
&             alfa**2*em*bb*hh+vis**2*alfa**2*em*cc*hh**2+&
&             2._dp*vis*alfa**2*em**2*cc*hh-vis**4*alfa**2*x0+&
&             vis**4*alfa**2*xm)/vis**3/(alfa-1._dp)/em

           end if !if(abs(vis)<=1.d-8)

           xc=xnow
           vec_tmp1(jj,kk)=vec_tmp2(jj,kk)
           vec_tmp2(jj,kk)=xnow
         else
           vnow=vprev
         end if !if(itime>2)

!        write(std_out,*) '07'
!        ##########################################################
!        ### 07. Correct positions
!        ###     These changes only applies for itime>1

         if(abs(vis)<=1.d-8)then
!          NON-DAMPED DYNAMICS (Pre-Code)
!          If the viscosity is too small, the equations become
!          ill conditioned due to rounding error so do regular
!          Verlet predictor Numerov corrector.
           x0=vec_tmp2(jj,kk)
           xm=vec_tmp1(jj,kk)
           xnow=2._dp*x0-xm&
&           + hh**2/em*fcart
         else
!          DAMPED DYNAMICS (Pre-Code)
!          These equations come from solving
!          m*d2x/dt2+vis*dx/dt=a+b*t+c*t**2
!          analytically under the boundary conditions that
!          x(0)=x0 and x(-h)=xm, and the following is the
!          expression for x(h). a, b and c are determined
!          from our knowledge of the driving forces.
           aa=fcart
           bb=(fcart-fprev)/hh
           x0=vec_tmp2(jj,kk)
           xm=vec_tmp1(jj,kk)
           alfa=exp(-vis*hh/em)
           xnow=( (-aa*hh*vis**2 +0.5_dp*bb*hh**2*vis**2&
&           +em*bb*hh*vis +x0*vis**3 -xm*vis**3)*alfa&
&           +aa*hh*vis**2 -em*bb*hh*vis&
&           +0.5_dp*bb*hh**2*vis**2 +x0*vis**3)/vis**3
!          End of choice between initialisation, damped
!          dynamics and non-damped dynamics
         end if

       end if !if(itime==1)

     end if !if(ab_mover%iatfix(jj,kk)==1)

!    write(std_out,*) '08'
!    ##########################################################
!    ### 08. Update history

     xcart(jj,kk)=xnow
     hist%histV(jj,kk,hist%ihist+1)=vnow

!    write(std_out,*) '09'
!    ##########################################################
!    ### 09. End loops of atoms and directions
   end do ! jj=1,3
 end do ! kk=1,ab_mover%natom

!write(std_out,*) '10'
!##########################################################
!### 10. Filling history with the new values

 hist%ihist=hist%ihist+1

!Compute xred from xcart, and rprimd
 call xredxcart(ab_mover%natom,-1,rprimd,xcart,xred)

 call var2hist(acell,hist,ab_mover%natom,rprim,rprimd,xcart,xred,zDEBUG)

!Change ncycle for itime>1
 if (icycle==4)then
   ncycle=1
 end if

!The last prediction is in itime=ntime-1
!Temporarily deactivated (MT sept. 2011)
 if (.false.) write(std_out,*) ntime
!if (itime==ntime-1)then
!if(itime==ntime-1)then
!deallocate(vec_tmp1,vec_tmp2)
!end if

 if (itime==1)then
   time=0.0_dp
   if (ab_mover%dtion<0)then
     write(std_out,*) 'Time=',time
   end if
 end if
 time=time+hh
 hist%histT(hist%ihist)=time

end subroutine pred_moldyn
!!***

!!****f* ABINIT/fdtion
!! NAME
!! fdtion
!!
!! FUNCTION
!! Compute the apropiated "dtion" from the present values
!! of forces, velocity and viscosity
!!
!! COPYRIGHT
!! Copyright (C) 1998-2012 ABINIT group (DCA, XG, GMR, SE)
!! This file is distributed under the terms of the
!! GNU General Public License, see ~abinit/COPYING
!! or http://www.gnu.org/copyleft/gpl.txt .
!!
!! INPUTS (in)
!! hist<type ab_movehistory>=Historical record of positions, forces
!!      |                    acell, stresses, and energies,
!!      |                    contains:
!!      | mxhist:  Maximun number of records
!!      | histA:   Historical record of acell(A) and rprimd(R)
!!      | histE:   Historical record of energy(E)
!!      | histEk:  Historical record of Ionic kinetic energy(Ek)
!!      | histT:   Historical record of time(T) (For MD or iteration for GO)
!!      | histR:   Historical record of rprimd(R)
!!      | histS:   Historical record of strten(S)
!!      | histV:   Historical record of velocity(V)
!!      | histXF:  Historical record of positions(X) and forces(F)
!! ab_mover<type ab_movetype>=Subset of dtset only related with
!!          |                 movement of ions and acell, contains:
!!          | dtion:  Time step
!!          ! natom:  Number of atoms
!!          | vis:    viscosity
!!          | iatfix: Index of atoms and directions fixed
!!          | amass:  Mass of ions
!! itime: Index of time iteration
!!
!! OUTPUT (out)
!! fdtion = time step computed
!!
!! NOTES
!!
!! PARENTS
!!      pred_moldyn
!!
!! CHILDREN
!!
!! SOURCE

#if defined HAVE_CONFIG_H
#include "config.h"
#endif

function fdtion(ab_mover,hist,itime)

! define dp,sixth,third,etc...
  use defs_basis
! type(ab_movetype), type(ab_movehistory)
  use defs_mover

!This section has been created automatically by the script Abilint (TD).
!Do not modify the following lines by hand.
#undef ABI_FUNC
#define ABI_FUNC 'fdtion'
!End of the abilint section

  implicit none

!Arguments ---------------------------------------------
!scalars
  type(ab_movetype),intent(in) :: ab_mover
  type(ab_movehistory),intent(in) :: hist
  integer,intent(in)    :: itime
  real(dp)      :: fdtion

!Local variables ------------------------------
!scalars
  integer  :: jj,kk
  real(dp) :: max,min,val
  real(dp) :: fcart,xc,vel,em

!************************************************************************

 max=0
 min=1e6

 do kk=1,ab_mover%natom
   em=ab_mover%amass(kk)
   do jj=1,3
     fcart=hist%histXF(jj,kk,3,hist%ihist)
     xc   =hist%histXF(jj,kk,1,hist%ihist)
     vel  =hist%histV(jj,kk,hist%ihist)

     if (vel>1e-8) then
       val=abs(1.0_dp/vel)
       write(std_out,*) 'vel',kk,jj,val
       if (val>max) max=val
       if (val<min) min=val
     end if

     if (fcart>1e-8) then
       val=sqrt(abs(2*em/fcart))
       write(std_out,*) 'forces',kk,jj,val,em,fcart
       if (val>max) max=val
       if (val<min) min=val
     end if

   end do

 end do

 write(std_out,*) "DTION max=",max
 write(std_out,*) "DTION min=",min

 if (itime==1)then
   fdtion=min/10
 else
   fdtion=min/10
 end if

 end function fdtion
!!***
