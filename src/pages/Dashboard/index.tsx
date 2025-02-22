import React from 'react';
import {
  EllipsisVerticalIcon,
  CircleStackIcon,
} from '@heroicons/react/24/solid';

const Dashboard: React.FC = () => {
  return (
    <div className=" w-full flex justify-between gap-4">
      <div className="">Dashboard Page</div>
      <Cards
        Course="Computer Systems"
        Semester="Cs 2025"
        LongName="CS2222222"
      />
    </div>
  );
};

type CardProps = {
  Course: string;
  Semester: string;
  LongName: string;
};
function Cards({ Course, Semester, LongName }: CardProps) {
  return (
    <div className="h-96 w-96 shadow-xs">
      <div className="rounded-lg h-full w-full bg-white overflow-hidden">
        <div className="h-1/2 bg-green-500 relative">
          <EllipsisVerticalIcon
            width={50}
            strokeWidth={2}
            className="absolute top-2 right-2"
          />
        </div>

        <a href="" className="">
          <div className="flex flex-col text-black p-2  h-auto w-aut gap-0">
            <span className="text-green-500">{Course}</span>
            <span>{LongName}</span>
            <span>{Semester} </span>
          </div>
        </a>

        <div className="text-black">
          <CircleStackIcon width={20} strokeWidth={2} />
        </div>
      </div>
    </div>
  );
}

export default Dashboard;
