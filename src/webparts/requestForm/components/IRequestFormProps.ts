import { WebPartContext } from '@microsoft/sp-webpart-base';

export interface IRequestFormProps {
  description: string;
  context: WebPartContext;
  siteUrl: string;
}
