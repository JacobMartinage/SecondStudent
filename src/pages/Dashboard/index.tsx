import React from 'react';
import { EllipsisVerticalIcon } from '@heroicons/react/24/solid';

const Dashboard: React.FC = () => {
  return (
    <div className=" w-full flex justify-between gap-4">
      <div className="text-green-500">Dashboard Page</div>
      <Cards Course="a" Semester="a" />
    </div>
  );
};

type CardProps = {
  Course: string;
  Semester: string;
};
function Cards({ Course, Semester }: CardProps) {
  return (
    <div className="h-[90px] w-[90px]">
      <div className="rounded-sm h-full w-full border-red-500 bg-white overflow-hidden">
        <div className="h-1/2 bg-green-500 relative">
          <EllipsisVerticalIcon
            width={20}
            strokeWidth={2}
            className="absolute top-2 right-2"
          />
        </div>
        <div className="">
          {Course}

          {Semester}
        </div>
      </div>
    </div>
  );
}

export default Dashboard;
